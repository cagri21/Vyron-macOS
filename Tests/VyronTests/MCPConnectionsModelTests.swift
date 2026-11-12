import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

private struct MCPModelRequest: Decodable {
    let id: String?
    let method: String
    let params: [String: DevelopmentJSONValue]?
}

private final class MCPModelStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [[String: DevelopmentJSONValue]] = []

    var toolCalls: [[String: DevelopmentJSONValue]] { lock.withLock { calls } }

    func reply(to request: URLRequest) throws -> (Int, Data) {
        if request.httpMethod == "DELETE" { return (204, Data()) }
        let body = try JSONDecoder().decode(MCPModelRequest.self, from: Self.body(of: request))
        if body.method == "notifications/initialized" { return (202, Data()) }
        let result: [String: DevelopmentJSONValue]
        switch body.method {
        case "initialize":
            result = ["protocolVersion": .string("2025-11-25"), "capabilities": .object(["tools": .object([:])])]
        case "tools/list":
            result = ["tools": .array([
                .object([
                    "name": .string("inspect_page"), "description": .string("Read the open design"),
                    "inputSchema": .object(["type": .string("object")]),
                    "annotations": .object(["readOnlyHint": .bool(true)])
                ]),
                .object([
                    "name": .string("create_rectangle"), "description": .string("Create a design rectangle"),
                    "inputSchema": .object(["type": .string("object")])
                ])
            ])]
        case "tools/call":
            lock.withLock { calls.append(body.params ?? [:]) }
            result = ["content": .array([.object(["type": .string("text"), "text": .string("Design operation completed")])])]
        default:
            throw URLError(.unsupportedURL)
        }
        let envelope: [String: DevelopmentJSONValue] = [
            "jsonrpc": .string("2.0"), "id": .string(body.id ?? ""), "result": .object(result)
        ]
        return (200, try JSONEncoder().encode(envelope))
    }

    private static func body(of request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            output.append(contentsOf: buffer.prefix(count))
        }
        return output
    }
}

private final class MCPModelStubRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nextPort = 33_000
    private var states: [Int: MCPModelStubState] = [:]

    func register(_ state: MCPModelStubState) -> Int {
        lock.withLock {
            nextPort += 1
            states[nextPort] = state
            return nextPort
        }
    }
    func state(for port: Int) -> MCPModelStubState? { lock.withLock { states[port] } }
    func remove(_ port: Int) { _ = lock.withLock { states.removeValue(forKey: port) } }
}

private final class MCPModelStubProtocol: URLProtocol, @unchecked Sendable {
    static let registry = MCPModelStubRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let port = request.url?.port, let state = Self.registry.state(for: port) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, data) = try state.reply(to: request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@MainActor
final class MCPConnectionsModelTests: XCTestCase {
    @MainActor
    private struct Harness {
        let directory: URL
        let state: MCPModelStubState
        let port: Int
        let profile: MCPConnectionProfile
        let model: MCPConnectionsModel
        let credentials: MCPCredentialStore

        func cleanUp() {
            model.shutdown()
            MCPModelStubProtocol.registry.remove(port)
            try? credentials.remove(for: profile.id)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func harness(corruptFile: Data? = nil) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronMCPModelTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = MCPModelStubState()
        let port = MCPModelStubProtocol.registry.register(state)
        let profile = MCPConnectionProfile(name: "Penpot fixture", endpoint: "http://127.0.0.1:\(port)/mcp", permission: .askForWrites)
        let fileURL = directory.appendingPathComponent("mcp-connections.json")
        if let corruptFile { try corruptFile.write(to: fileURL) }
        else { try MCPConnectionStore(fileURL: fileURL).save([profile]) }
        let credentials = MCPCredentialStore(service: "com.vyron.tests.mcp.\(UUID())")
        let model = MCPConnectionsModel(
            store: MCPConnectionStore(fileURL: fileURL),
            credentials: credentials
        ) { profile, secrets in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MCPModelStubProtocol.self]
            return try MCPClient(profile: profile, secrets: secrets, configuration: configuration)
        }
        return Harness(directory: directory, state: state, port: port, profile: profile, model: model, credentials: credentials)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The MCP connection did not reach its expected state")
        throw CancellationError()
    }

    private func connectedSession(_ test: Harness, mode: ComposerMode = .agent) async throws -> MCPToolSession {
        test.model.connect(test.profile)
        try await waitUntil { !test.model.busy.contains(test.profile.id) }
        XCTAssertTrue(test.model.isConnected(test.profile.id), test.model.error ?? "Expected a connected fixture")
        return try test.model.snapshot(mode: mode)
    }

    private func call(for tool: String, session: MCPToolSession) throws -> DevelopmentToolCall {
        let name = try XCTUnwrap(session.bindings.first { $0.value.tool.name == tool }?.key)
        return DevelopmentToolCall(name: name, arguments: ["width": .number(120), "label": .string("Reviewable rectangle")])
    }

    func testDecliningWriteReviewMakesNoTransportToolCall() async throws {
        let test = try harness()
        defer { test.cleanUp() }
        let session = try await connectedSession(test)
        let call = try call(for: "create_rectangle", session: session)
        let operation = Task { try await test.model.execute(call, session: session) }
        try await waitUntil { test.model.pendingReview != nil }
        let review = try XCTUnwrap(test.model.pendingReview)
        XCTAssertEqual(review.connectionName, test.profile.name)
        XCTAssertEqual(review.toolName, "create_rectangle")
        XCTAssertTrue(review.arguments.contains("Reviewable rectangle"))
        XCTAssertTrue(test.state.toolCalls.isEmpty)
        test.model.respondToReview(false)
        let result = try await operation.value
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("declined"))
        XCTAssertTrue(test.state.toolCalls.isEmpty)
        XCTAssertNil(test.model.pendingReview)
    }

    func testApprovingWriteReviewExecutesExactToolCallOnlyOnce() async throws {
        let test = try harness()
        defer { test.cleanUp() }
        let session = try await connectedSession(test)
        let call = try call(for: "create_rectangle", session: session)
        let operation = Task { try await test.model.execute(call, session: session) }
        try await waitUntil { test.model.pendingReview != nil }
        XCTAssertTrue(test.state.toolCalls.isEmpty)
        test.model.respondToReview(true)
        test.model.respondToReview(true)
        let result = try await operation.value
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.text, "Design operation completed")
        XCTAssertEqual(test.state.toolCalls.count, 1)
        XCTAssertEqual(test.state.toolCalls.first?["name"], .string("create_rectangle"))
        XCTAssertEqual(test.state.toolCalls.first?["arguments"], .object(call.function.arguments))
        XCTAssertNil(test.model.pendingReview)

        let secondOperation = Task { try await test.model.execute(call, session: session) }
        try await waitUntil { test.model.pendingReview != nil }
        XCTAssertEqual(test.state.toolCalls.count, 1, "Approval applies only to the reviewed invocation")
        test.model.respondToReview(false)
        let secondResult = try await secondOperation.value
        XCTAssertTrue(secondResult.isError)
        XCTAssertEqual(test.state.toolCalls.count, 1)
    }

    func testCancellingWhileReviewIsPendingClearsReviewAndCallsNoTool() async throws {
        let test = try harness()
        defer { test.cleanUp() }
        let session = try await connectedSession(test)
        let call = try call(for: "create_rectangle", session: session)
        let operation = Task { try await test.model.execute(call, session: session) }
        try await waitUntil { test.model.pendingReview != nil }
        operation.cancel()
        do { _ = try await operation.value; XCTFail("Expected the pending action to be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(test.model.pendingReview)
        XCTAssertTrue(test.state.toolCalls.isEmpty)
        test.model.respondToReview(true)
        XCTAssertTrue(test.state.toolCalls.isEmpty, "A late approval must not revive the cancelled action")
    }

    func testDisconnectedAndStaleSnapshotsCannotExecuteButFreshReadSessionCan() async throws {
        let test = try harness()
        defer { test.cleanUp() }
        let original = try await connectedSession(test)
        let oldCall = try call(for: "inspect_page", session: original)
        test.model.disconnect(test.profile.id)
        do { _ = try await test.model.execute(oldCall, session: original); XCTFail("A disconnected session must be rejected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("connection changed")) }
        let fresh = try await connectedSession(test, mode: .plan)
        XCTAssertEqual(fresh.tools.count, 1, "Plan mode exposes only the read-only integration tool")
        do { _ = try await test.model.execute(oldCall, session: original); XCTFail("Reconnecting must not revive an earlier snapshot") }
        catch { XCTAssertTrue(error.localizedDescription.contains("connection changed")) }
        XCTAssertTrue(test.state.toolCalls.isEmpty)
        XCTAssertNil(test.model.pendingReview)
        let freshCall = try call(for: "inspect_page", session: fresh)
        let result = try await test.model.execute(freshCall, session: fresh)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(test.state.toolCalls.count, 1)
        XCTAssertEqual(test.state.toolCalls.first?["name"], .string("inspect_page"))
        XCTAssertNil(test.model.pendingReview)
    }

    func testCorruptPersistenceIsPreservedAndCannotBeOverwritten() throws {
        let original = Data("{broken configuration, preserve this content".utf8)
        let test = try harness(corruptFile: original)
        defer { test.cleanUp() }
        XCTAssertTrue(test.model.profiles.isEmpty)
        XCTAssertTrue(test.model.error?.contains("preserved") == true)
        XCTAssertFalse(test.model.save(test.profile, secrets: MCPConnectionSecrets()))
        test.model.remove(test.profile.id)
        XCTAssertEqual(try Data(contentsOf: test.directory.appendingPathComponent("mcp-connections.json")), original)
        XCTAssertTrue(test.state.toolCalls.isEmpty)
    }
}
