import Foundation
import XCTest
import Darwin
@testable import VyronCore

private final class MCPStubState: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, [String: String], String)
    private let lock = NSLock()
    private var handler: Handler?
    private var count = 0
    func set(_ handler: Handler?) { lock.withLock { self.handler = handler; count = 0 } }
    func handle(_ request: URLRequest) throws -> (Int, [String: String], String) {
        let value = lock.withLock { count += 1; return handler }
        guard let value else { throw URLError(.unsupportedURL) }
        return try value(request)
    }
    var requests: Int { lock.withLock { count } }
}

private final class MCPStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = MCPStubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, body) = try Self.state.handle(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let bytes = Data(body.utf8)
            // Deliberately split in the middle of an SSE line or UTF-8 sequence.
            let cut = bytes.count / 2
            client?.urlProtocol(self, didLoad: Data(bytes.prefix(cut)))
            client?.urlProtocol(self, didLoad: Data(bytes.dropFirst(cut)))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func mcpBody(_ request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&bytes, maxLength: bytes.count)
            if read <= 0 { break }
            data.append(contentsOf: bytes.prefix(read))
        }
    }
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

private func mcpReply(_ body: [String: Any], result: [String: Any]) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": body["id"]!, "result": result]), as: UTF8.self)
}

private var mcpReadTool: [String: Any] { [
    "name": "inspect_page", "description": "Inspect the current page", "inputSchema": ["type": "object"], "annotations": ["readOnlyHint": true]
] }

final class MCPClientTests: XCTestCase, @unchecked Sendable {
    override func tearDown() { MCPStubProtocol.state.set(nil); super.tearDown() }

    private func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MCPStubProtocol.self]; return config
    }

    private func client(permission: MCPPermission = .readOnly, secrets: MCPConnectionSecrets = MCPConnectionSecrets()) throws -> MCPClient {
        try MCPClient(profile: MCPConnectionProfile(name: "Fixture", endpoint: "https://mcp.example.test/mcp", permission: permission), secrets: secrets, configuration: configuration())
    }

    func testEndpointAndCommandValidationProtectsCredentialsAndRemoteTransport() throws {
        XCTAssertEqual(try MCPEndpoint.validated("http://localhost:4401/mcp").host, "localhost")
        for value in ["http://remote.example/mcp", "https://user:secret@remote.example/mcp", "https://remote.example/mcp?userToken=secret", "file:///tmp/mcp", "https://remote.example/mcp#fragment"] {
            XCTAssertThrowsError(try MCPEndpoint.validated(value), value)
        }
        XCTAssertThrowsError(try MCPConnectionProfile(name: "", endpoint: "https://mcp.example/mcp").validated())
        XCTAssertThrowsError(try MCPConnectionProfile(name: "Command", transport: .stdio, command: "npx -y server").validated())
        XCTAssertThrowsError(try MCPConnectionProfile(name: "Command", transport: .stdio, command: "./server").validated())
        XCTAssertEqual(try MCPConnectionProfile(name: "Command", transport: .stdio, command: "/path with spaces/server", arguments: ["literal $(text)"]).validated().arguments, ["literal $(text)"])
    }

    func testPenpotURLQuerySecretsAreSeparatedBeforePersistence() throws {
        let split = try MCPEndpoint.separateSecrets("https://design.penpot.app/mcp/stream?userToken=private%2Bkey")
        XCTAssertEqual(split.endpoint, "https://design.penpot.app/mcp/stream")
        XCTAssertEqual(split.queryParameters, ["userToken": "private+key"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MCPConnectionStore(fileURL: directory.appendingPathComponent("connections.json"))
        let profile = MCPConnectionProfile(name: "Penpot", endpoint: split.endpoint)
        try store.save([profile])
        XCTAssertEqual(try store.load(), [profile])
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("userToken")); XCTAssertFalse(text.contains("private"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertThrowsError(try store.save([profile, profile]))
        XCTAssertThrowsError(try MCPEndpoint.separateSecrets("https://mcp.example/mcp?key=1&key=2"))
    }

    func testCredentialValidationRejectsHeaderInjectionAndProtocolHeaderOverrides() throws {
        XCTAssertThrowsError(try MCPConnectionSecrets(bearerToken: "key\r\nInjected: yes").validated())
        XCTAssertThrowsError(try MCPConnectionSecrets(headers: ["Mcp-Session-Id": "override"]).validated())
        XCTAssertThrowsError(try MCPConnectionSecrets(headers: ["X-Key": "one", "x-key": "two"]).validated())
        XCTAssertThrowsError(try MCPConnectionSecrets(environment: ["BAD=KEY": "value"]).validated())
        XCTAssertNoThrow(try MCPConnectionSecrets(headers: ["X-API-Key": "secret"], environment: ["API_KEY": "secret"]).validated())
    }

    func testReadOnlyClassificationDoesNotTrustCodeExecutionOrExportHints() {
        let hints: [String: DevelopmentJSONValue] = ["readOnlyHint": .bool(true)]
        XCTAssertTrue(MCPTool(name: "inspect_page", annotations: hints).isReadOnly)
        XCTAssertFalse(MCPTool(name: "inspect_page").isReadOnly)
        for name in ["execute_code", "executeCode", "runJS", "export_shape", "setColor", "delete_page"] {
            XCTAssertFalse(MCPTool(name: name, annotations: hints).isReadOnly, name)
        }
    }

    func testHTTPInitializationPaginationAndToolCallCarryNegotiatedSessionAndSecrets() async throws {
        MCPStubProtocol.state.set { request in
            XCTAssertEqual(request.url?.query, "userToken=private-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bearer-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "header-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json, text/event-stream")
            let body = try mcpBody(request)
            if body["method"] as? String == "initialize" {
                XCTAssertNil(request.value(forHTTPHeaderField: "Mcp-Session-Id"))
                return (200, ["Content-Type": "application/json", "Mcp-Session-Id": "session-123"], try mcpReply(body, result: ["protocolVersion": "2025-06-18", "capabilities": ["tools": [:]]]))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Mcp-Session-Id"), "session-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "MCP-Protocol-Version"), "2025-06-18")
            if body["method"] as? String == "notifications/initialized" { return (202, [:], "") }
            if body["method"] as? String == "tools/list" {
                if (body["params"] as? [String: Any])?["cursor"] as? String == "page-two" {
                    return (200, ["Content-Type": "application/json"], try mcpReply(body, result: ["tools": []]))
                }
                return (200, ["Content-Type": "application/json"], try mcpReply(body, result: ["tools": [mcpReadTool], "nextCursor": "page-two"]))
            }
            XCTAssertEqual(body["method"] as? String, "tools/call")
            XCTAssertEqual((body["params"] as? [String: Any])?["name"] as? String, "inspect_page")
            return (200, ["Content-Type": "application/json"], try mcpReply(body, result: ["content": [["type": "text", "text": "Design inspected"]], "structuredContent": ["count": 3]]))
        }
        let value = try client(secrets: MCPConnectionSecrets(bearerToken: "bearer-key", headers: ["X-API-Key": "header-key"], queryParameters: ["userToken": "private-key"]))
        let tools = try await value.connect()
        XCTAssertEqual(tools.map(\.name), ["inspect_page"])
        let result = try await value.callTool(name: "inspect_page", arguments: [:])
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.readableText.contains("Design inspected"))
        XCTAssertTrue(result.readableText.contains("count"))
        XCTAssertEqual(MCPStubProtocol.state.requests, 5)
    }

    func testSSEIgnoresProgressAndReturnsMatchingMultilineResult() async throws {
        MCPStubProtocol.state.set { request in
            let body = try mcpBody(request)
            if body["method"] as? String == "notifications/initialized" { return (202, [:], "") }
            let result: [String: Any] = body["method"] as? String == "initialize"
                ? ["protocolVersion": "2025-11-25", "capabilities": ["tools": [:]]]
                : body["method"] as? String == "tools/list" ? ["tools": [mcpReadTool]]
                : ["content": [["type": "text", "text": "Layer café inspected"]], "isError": false]
            let reply = try mcpReply(body, result: result)
            return (200, ["Content-Type": "text/event-stream"], ": keep-alive\r\ndata:\r\n\r\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\"}\r\n\r\ndata: \(reply)\r\n\r\n")
        }
        let value = try client()
        _ = try await value.connect()
        let result = try await value.callTool(name: "inspect_page", arguments: [:])
        XCTAssertEqual(result.readableText, "Layer café inspected")
    }

    func testWritesRequirePermissionAndExactCallApproval() async throws {
        MCPStubProtocol.state.set { request in
            let body = try mcpBody(request)
            if body["method"] as? String == "notifications/initialized" { return (202, [:], "") }
            let result: [String: Any] = body["method"] as? String == "initialize"
                ? ["protocolVersion": "2025-11-25", "capabilities": ["tools": [:]]]
                : body["method"] as? String == "tools/list"
                    ? ["tools": [["name": "execute_code", "inputSchema": ["type": "object"], "annotations": ["readOnlyHint": true]]]]
                    : ["content": [["type": "text", "text": "Changed"]]]
            return (200, ["Content-Type": "application/json"], try mcpReply(body, result: result))
        }
        let value = try client(permission: .askForWrites)
        _ = try await value.connect()
        do { _ = try await value.callTool(name: "execute_code", arguments: [:]); XCTFail("Expected review requirement") }
        catch { XCTAssertTrue(error.localizedDescription.contains("approve")) }
        XCTAssertEqual(MCPStubProtocol.state.requests, 3)
        let result = try await value.callTool(name: "execute_code", arguments: [:], approved: true)
        XCTAssertEqual(result.readableText, "Changed")
        let readOnly = try client()
        _ = try await readOnly.connect()
        do { _ = try await readOnly.callTool(name: "execute_code", arguments: [:], approved: true); XCTFail("Read only cannot be overridden") }
        catch { XCTAssertTrue(error.localizedDescription.contains("read-only")) }
    }

    func testToolErrorsArePreservedAndTransportErrorsDoNotLeakToken() async throws {
        MCPStubProtocol.state.set { _ in throw URLError(.cannotConnectToHost, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://example/mcp?userToken=secret-123"]) }
        let value = try client()
        do { _ = try await value.connect(); XCTFail("Expected transport error") }
        catch { XCTAssertFalse(error.localizedDescription.contains("secret-123")); XCTAssertTrue(error is MCPError) }
        let error = try JSONDecoder().decode(MCPToolResult.self, from: Data(#"{"isError":true,"content":[{"type":"text","text":"No Penpot file connected"}]}"#.utf8))
        XCTAssertTrue(error.isError)
        XCTAssertEqual(error.readableText, "No Penpot file connected")
    }

    func testInvalidProtocolAndRepeatedPaginationAreRejected() async throws {
        MCPStubProtocol.state.set { request in
            let body = try mcpBody(request)
            if body["method"] as? String == "notifications/initialized" { return (202, [:], "") }
            let result: [String: Any] = body["method"] as? String == "initialize"
                ? ["protocolVersion": "2025-11-25", "capabilities": ["tools": [:]]]
                : ["tools": [], "nextCursor": "loop"]
            return (200, ["Content-Type": "application/json"], try mcpReply(body, result: result))
        }
        let value = try client()
        do { _ = try await value.connect(); XCTFail("Expected pagination rejection") }
        catch { XCTAssertTrue(error.localizedDescription.contains("pagination")) }
        XCTAssertEqual(MCPStubProtocol.state.requests, 4)
    }

    func testStdioServerUsesLiteralArgumentsAndClosesProcessOnDisconnect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let script = #"""
        import json, os, sys
        open(sys.argv[1], 'w').write(str(os.getpid()))
        for line in sys.stdin:
            message = json.loads(line)
            method = message.get('method')
            if 'id' not in message: continue
            if method == 'initialize':
                result = {'protocolVersion':'2025-11-25', 'capabilities': {'tools':{}}}
            elif method == 'tools/list':
                result = {'tools':[{'name':'inspect_page','inputSchema':{'type':'object'},'annotations':{'readOnlyHint':True}}]}
            else:
                result = {'content':[{'type':'text','text':sys.argv[2] + ':' + os.environ['MCP_TEST_VALUE']}]}
            print(json.dumps({'jsonrpc':'2.0','id':message['id'],'result':result}), flush=True)
        """#
        let value = try MCPClient(profile: MCPConnectionProfile(name: "Python fixture", transport: .stdio, command: "/usr/bin/python3", arguments: ["-u", "-c", script, pidFile.path, "literal $(no shell)"]), secrets: MCPConnectionSecrets(environment: ["MCP_TEST_VALUE": "injected"]), timeout: 5)
        let tools = try await value.connect()
        XCTAssertEqual(tools.map(\.name), ["inspect_page"])
        let result = try await value.callTool(name: "inspect_page", arguments: [:])
        XCTAssertEqual(result.readableText, "literal $(no shell):injected")
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        await value.disconnect()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(kill(pid, 0), -1, "The configured stdio process must be terminated")
    }

    func testStdioTimeoutIsBounded() async throws {
        let value = try MCPClient(profile: MCPConnectionProfile(name: "Unresponsive fixture", transport: .stdio, command: "/usr/bin/python3", arguments: ["-u", "-c", "import time; time.sleep(10)"]), timeout: 0.2)
        let start = Date()
        do { _ = try await value.connect(); XCTFail("Expected deadline") }
        catch { XCTAssertEqual(error as? MCPError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testStdioTimeoutStopsLauncherDescendants() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stoppedFile = pidFile.appendingPathExtension("stopped")
        defer {
            try? FileManager.default.removeItem(at: pidFile)
            try? FileManager.default.removeItem(at: stoppedFile)
        }
        let script = #"""
        import os, signal, sys, time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        child = os.fork()
        if child == 0:
            def stopped(signum, frame):
                open(sys.argv[2], 'w').write('group signal received')
                sys.exit(0)
            signal.signal(signal.SIGTERM, stopped)
            open(sys.argv[1], 'w').write(str(os.getpid()))
            time.sleep(10)
        else:
            # The launcher ignores termination; only the process-group signal reaches the child.
            os.waitpid(child, 0)
            time.sleep(10)
        """#
        let value = try MCPClient(profile: MCPConnectionProfile(name: "Launcher fixture", transport: .stdio, command: "/usr/bin/python3", arguments: ["-u", "-c", script, pidFile.path, stoppedFile.path]), timeout: 1)
        do { _ = try await value.connect(); XCTFail("Expected deadline") }
        catch { XCTAssertEqual(error as? MCPError, .timeout) }
        let child = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(try String(contentsOf: stoppedFile, encoding: .utf8), "group signal received")
        XCTAssertEqual(kill(child, 0), -1, "The stdio launcher's descendant must be terminated")
    }
}
