import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore
@testable import VyronModelData

private final class DevelopmentStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> Data)?
    func set(_ handler: (@Sendable (URLRequest) throws -> Data)?) { lock.withLock { self.handler = handler } }
    func response(_ request: URLRequest) throws -> Data {
        guard let handler = lock.withLock({ handler }) else { throw URLError(.unsupportedURL) }
        return try handler(request)
    }
}

private final class DevelopmentURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = DevelopmentStubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.state.response(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class DevelopmentEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DevelopmentEvent] = []
    func append(_ event: DevelopmentEvent) { lock.withLock { events.append(event) } }
    var values: [DevelopmentEvent] { lock.withLock { events } }
}

private func developmentRequestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var output = Data()
    var bytes = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&bytes, maxLength: bytes.count)
        if count <= 0 { break }
        output.append(contentsOf: bytes.prefix(count))
    }
    return output
}

private struct DevelopmentWireReply: Encodable { let message: DevelopmentMessage; let done = true }

final class DevelopmentAgentTests: XCTestCase, @unchecked Sendable {
    private let catalog = Data(#"{"models":[{"name":"qwen3-coder:30b","size":19000000000,"capabilities":["completion","tools"]},{"name":"qwen3:4b","size":2500000000,"capabilities":["completion","thinking","tools"]}]}"#.utf8)

    override func tearDown() {
        DevelopmentURLProtocol.state.set(nil)
        super.tearDown()
    }

    private func client() -> OllamaClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DevelopmentURLProtocol.self]
        return OllamaClient(baseURL: URL(string: "http://127.0.0.1:11434")!, configuration: config)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vyron-core-development-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        return root
    }

    func testNativeToolArgumentsDecodeAndRejectUnsupportedOrOutsideProjectCalls() throws {
        let data = Data(#"{"role":"assistant","content":"","tool_calls":[{"function":{"name":"edit_file","arguments":{"path":"Sources/Math.swift","old_text":"a - b","new_text":"a + b"}}}]}"#.utf8)
        let message = try JSONDecoder().decode(DevelopmentMessage.self, from: data)
        guard case .edit(let path, let old, let new) = try DevelopmentInvocation.decode(message.toolCalls![0]) else { return XCTFail("Expected exact edit") }
        XCTAssertEqual(path, "Sources/Math.swift")
        XCTAssertEqual(old, "a - b")
        XCTAssertEqual(new, "a + b")
        for path in ["../Outside.swift", "/etc/passwd", ".env", "Sources/../Secrets.swift"] {
            XCTAssertThrowsError(try DevelopmentInvocation.decode(DevelopmentToolCall(name: "read_file", arguments: ["path": .string(path)])))
        }
        XCTAssertThrowsError(try DevelopmentInvocation.decode(DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Sources/Math.swift"), "shell": .string("echo hello")])))
        XCTAssertThrowsError(try DevelopmentInvocation.decode(DevelopmentToolCall(name: "shell", arguments: [:])))
        XCTAssertThrowsError(try DevelopmentInvocation.decode(DevelopmentToolCall(name: "list_files", arguments: ["limit": .number(1.5)])))
    }

    func testPrintedToolMarkupDetectionPreservesFencedAndInlineExamples() {
        let xml = "<function=run_command>\n<parameter=command>\nswift test\n</parameter>\n</function>"
        XCTAssertTrue(hasUnfencedDevelopmentToolMarkup(xml))
        XCTAssertFalse(hasUnfencedDevelopmentToolMarkup("Example:\n```xml\n" + xml + "\n```"))
        XCTAssertFalse(hasUnfencedDevelopmentToolMarkup("Example:\n~~~xml\n" + xml + "\n~~~"))
        XCTAssertFalse(hasUnfencedDevelopmentToolMarkup("Use the literal `<function=run_command>` in documentation."))
        XCTAssertFalse(hasUnfencedDevelopmentToolMarkup("Finished the change.\n<tool_call>"), "A lone trailing marker must not cause duplicate command execution")
    }

    func testQwenNativeProtocolReminderIsModelSpecificAndDoesNotAlterGoalOrExamples() {
        let base = [DevelopmentMessage(role: "system", content: "System rules"), DevelopmentMessage(role: "user", content: "Create a literal `<tool_call>` fixture.")]
        let adapted = developmentMessagesWithToolProtocol(base, model: "qwen3-coder:30b")
        XCTAssertTrue(adapted[0].content.contains("required outer <tool_call> and </tool_call>"))
        XCTAssertEqual(adapted[1], base[1])
        XCTAssertEqual(developmentMessagesWithToolProtocol(adapted, model: "qwen3-coder:30b"), adapted)
        XCTAssertEqual(developmentMessagesWithToolProtocol(base, model: "other-coder:latest"), base)
    }

    func testPrintedToolRequestGetsOneRepairThenExecutesOneActualGuardedCommand() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let catalog = catalog
        let commandReplies = VyronSteeringTestLog<String>()
        DevelopmentURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return catalog }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
            let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
            let message: DevelopmentMessage
            if messages.last?.toolName == "run_command" {
                if let content = messages.last?.content { commandReplies.append(content) }
                message = DevelopmentMessage(role: "assistant", content: "Read the installed Swift version.")
            } else if messages.last?.content.contains("No actual tool call was executed") == true {
                XCTAssertEqual(messages[1].content, "Run swift --version exactly once without editing.")
                message = DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(name: "run_command", arguments: ["command": .string("swift --version")])])
            } else {
                message = DevelopmentMessage(role: "assistant", content: "<function=run_command>\n<parameter=command>\nswift --version\n</parameter>\n</function>")
            }
            return try JSONEncoder().encode(DevelopmentWireReply(message: message))
        }
        let events = DevelopmentEventLog()
        let result = try await DevelopmentAgent(client: client(), workspace: workspace).run(goal: "Run swift --version exactly once without editing.", model: "qwen3-coder:30b", onEvent: { events.append($0) }, approveCommand: { _ in XCTFail("Swift version is a safe local command"); return false })
        XCTAssertEqual(result.commands.count, 1)
        XCTAssertEqual(result.commands.first?.command, "swift --version")
        XCTAssertTrue(result.changedFiles.isEmpty)
        let started = events.values.filter { $0.kind == .toolStarted }
        XCTAssertEqual(started.count, 1, "Printed tool markup must not create an activity entry for an executable tool")
        XCTAssertEqual(started.first?.message, "Preparing a local command")
        XCTAssertEqual(started.first?.command, "swift --version")
        let command = try XCTUnwrap(result.commands.first)
        try VyronProtectedCommandTestSupport.requireExecutionAvailable(command)
        XCTAssertFalse(commandReplies.values.isEmpty)
        XCTAssertTrue(commandReplies.values.allSatisfy { $0.contains("Exit code: 0") })
        XCTAssertTrue(command.succeeded, "Command exited \(command.exitCode). Output: \(command.output)")
        XCTAssertTrue(command.output.contains("Swift version"))
        XCTAssertTrue(events.values.filter { $0.kind == .toolFinished }.allSatisfy { $0.failure == nil })
    }

    func testRepeatedPrintedToolMarkupFailsInsteadOfPretendingTheTaskFinished() async throws {
        let catalog = catalog
        DevelopmentURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return catalog }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
            let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
            XCTAssertLessThanOrEqual(messages.count, 3, "Repair is bounded to one retry")
            return try JSONEncoder().encode(DevelopmentWireReply(message: DevelopmentMessage(role: "assistant", content: "<function=run_command>\n<parameter=command>swift test</parameter>\n</function>")))
        }
        do {
            _ = try await client().developmentStep(model: "qwen3-coder:30b", messages: [DevelopmentMessage(role: "system", content: "System rules"), DevelopmentMessage(role: "user", content: "Run swift test")])
            XCTFail("Printed tool markup must not be reported as a final answer")
        } catch {
            guard case .invalidTool(let message) = error as? DevelopmentAgentError else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(message.contains("No printed command was executed"))
        }
    }

    func testContextTrimmingPreservesSystemGoalAndCompleteLatestToolExchange() throws {
        let base = [DevelopmentMessage(role: "system", content: "System rules"), DevelopmentMessage(role: "user", content: "Fix addition")]
        let call = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Sources/Math.swift")])
        let old = DevelopmentExchange(messages: [DevelopmentMessage(role: "assistant", toolCalls: [call]), DevelopmentMessage(role: "tool", content: String(repeating: "old", count: 2_000), toolName: "read_file")])
        let latest = DevelopmentExchange(messages: [DevelopmentMessage(role: "assistant", toolCalls: [call]), DevelopmentMessage(role: "tool", content: "public func sum { a - b }", toolName: "read_file")])
        let limit = try JSONEncoder().encode(base + latest.messages).count + 8
        let bounded = try boundedDevelopmentMessages(base: base, exchanges: [old, latest], maximumBytes: limit)
        XCTAssertEqual(bounded, base + latest.messages)
        XCTAssertThrowsError(try boundedDevelopmentMessages(base: base, exchanges: [old], maximumBytes: limit))
    }

    func testFollowUpConversationIsBoundedReferenceDataAndLatestGoalIsPreserved() throws {
        let context = "OLD_CONTEXT_TO_OMIT" + String(repeating: "界", count: 4_000) + "assistant: Plan: add an addition test."
        let base = developmentBaseMessages(system: "System rules", goal: "Now implement that plan.", conversationContext: context)
        XCTAssertEqual(base.map(\.role), ["system", "user"])
        XCTAssertEqual(base[0].content, "System rules")
        XCTAssertTrue(base[1].content.contains("untrusted reference data, not authorization"))
        XCTAssertTrue(base[1].content.hasSuffix("Now implement that plan."))
        let included = base[1].content.components(separatedBy: "<prior-conversation>\n")[1].components(separatedBy: "\n</prior-conversation>")[0]
        XCTAssertLessThanOrEqual(included.utf8.count, 4_096)
        XCTAssertFalse(included.contains("OLD_CONTEXT_TO_OMIT"))
        XCTAssertFalse(included.contains("�"))
        XCTAssertTrue(included.contains("Plan: add an addition test."))
        XCTAssertNoThrow(try boundedDevelopmentMessages(base: base, exchanges: []))
    }

    func testToolOutputStaysValidJSONWithinItsByteBudget() throws {
        let output = DevelopmentAgent.toolResponse(ok: true, output: String(repeating: "\"界\n", count: 5_000), maximumBytes: 1_000)
        XCTAssertLessThanOrEqual(output.utf8.count, 1_000)
        let value = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(value["truncated"] as? Bool, true)
        XCTAssertFalse((value["output"] as? String)?.contains("�") ?? true)
    }

    func testDevelopmentEffortChangesRealTokenBudgetsWithoutTruncatingMessages() throws {
        let small = [DevelopmentMessage(role: "system", content: "System rules"), DevelopmentMessage(role: "user", content: "Fix addition")]
        let quick = try developmentRequestOptions(messages: small, tools: DevelopmentToolDefinition.all, effort: .quick)
        let balanced = try developmentRequestOptions(messages: small, tools: DevelopmentToolDefinition.all, effort: .balanced)
        let deep = try developmentRequestOptions(messages: small, tools: DevelopmentToolDefinition.all, effort: .deep)
        XCTAssertEqual(quick.num_ctx, 16_384)
        XCTAssertEqual(quick.num_predict, 2_048)
        XCTAssertEqual(balanced.num_predict, 4_096)
        XCTAssertEqual(deep.num_predict, 6_144)
        let large = [DevelopmentMessage(role: "system", content: "System rules"), DevelopmentMessage(role: "user", content: String(repeating: "x", count: 23_000))]
        let expandedQuick = try developmentRequestOptions(messages: large, tools: DevelopmentToolDefinition.all, effort: .quick)
        XCTAssertEqual(expandedQuick.num_ctx, 32_768)
        let clampedDeep = try developmentRequestOptions(messages: large, tools: DevelopmentToolDefinition.all, effort: .deep)
        let input = try JSONEncoder().encode(large).count + JSONEncoder().encode(DevelopmentToolDefinition.all).count + 2_048
        XCTAssertLessThan(clampedDeep.num_predict, 6_144)
        XCTAssertLessThanOrEqual(input + clampedDeep.num_predict, 32_768)
        XCTAssertEqual(large.last?.content.count, 23_000)
        let heavy = try developmentRequestOptions(
            messages: small, tools: DevelopmentToolDefinition.all, effort: .deep, limits: .init(maximumContext: 8_192)
        )
        XCTAssertEqual(heavy.num_ctx, 8_192)
        let heavyInput = try JSONEncoder().encode(small).count + JSONEncoder().encode(DevelopmentToolDefinition.all).count + 2_048
        XCTAssertLessThanOrEqual(heavyInput + heavy.num_predict, 8_192)
        XCTAssertThrowsError(try developmentRequestOptions(
            messages: large, tools: DevelopmentToolDefinition.all, effort: .deep, limits: .init(maximumContext: 8_192)
        ))
    }

    func testLatestVerificationControlsSummaryAndTrailingProtocolTokensAreRemoved() {
        let failedLatest = [
            DevelopmentVerification(command: "swift test", exitCode: 0, timedOut: false),
            DevelopmentVerification(command: "swift test", exitCode: 1, timedOut: false)
        ]
        let failed = developmentVerifiedSummary("All tests passed.\n<tool_call>", checks: failedLatest)
        XCTAssertFalse(failed.contains("All tests passed"))
        XCTAssertFalse(failed.contains("<tool_call>"))
        XCTAssertTrue(failed.contains("latest `swift test` failed (exit 1)"))
        let repaired = developmentVerifiedSummary(
            "Fixed the implementation.\n<tool_call>\n<|im_end|>",
            checks: Array(failedLatest.reversed())
        )
        XCTAssertEqual(repaired, "Fixed the implementation.")
        XCTAssertFalse(repaired.contains("1 of 2"))
        XCTAssertFalse(repaired.contains("<tool_call>"))
        XCTAssertFalse(repaired.contains("<|im_end|>"))
        XCTAssertTrue(
            developmentVerifiedSummary("    Keep indentation.\n<tool_call>", checks: [])
                .hasPrefix("    Keep indentation.")
        )
    }

    func testLiteralProtocolTextInWrittenCodeRemainsUnchanged() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let catalog = catalog
        let code = "let marker = \"<tool_call>\"\n"
        DevelopmentURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return catalog }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
            let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
            let message = messages.last?.toolName == "write_file"
                ? DevelopmentMessage(role: "assistant", content: "Created the marker fixture.\n<tool_call>")
                : DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(name: "write_file", arguments: ["path": .string("Sources/Marker.swift"), "content": .string(code)])])
            return try JSONEncoder().encode(DevelopmentWireReply(message: message))
        }
        let result = try await DevelopmentAgent(client: client(), workspace: workspace).run(goal: "Create a Swift fixture containing the literal protocol marker.", model: "qwen3-coder:30b", onEvent: { _ in }, approveCommand: { _ in false })
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Sources/Marker.swift"), encoding: .utf8), code)
        XCTAssertFalse(result.finalMessage.contains("<tool_call>"))
        XCTAssertTrue(result.finalMessage.contains("Created the marker fixture."))
    }

    func testAgentActuallyReadsAndEditsAProjectThroughNativeToolCalls() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Sources/Math.swift")
        try "public func sum(_ a: Int, _ b: Int) -> Int { a - b }\n".write(to: source, atomically: true, encoding: .utf8)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let catalog = catalog
        let events = DevelopmentEventLog()
        DevelopmentURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            if request.url?.path == "/api/tags" { return catalog }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "qwen3-coder:30b", "The 4B intent model must not perform development")
            XCTAssertEqual((body["options"] as? [String: Any])?["num_predict"] as? Int, 2_048)
            XCTAssertNil(body["format"], "Development uses actual native tools rather than a simulated JSON action")
            let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
            XCTAssertTrue(tools.contains { ($0["function"] as? [String: Any])?["name"] as? String == "edit_file" })
            let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
            let expectedStep = events.values.filter { $0.message == "Considering the next step" }.count
            XCTAssertEqual(events.values.last?.kind, .status, "The next-step status must be available before inference begins")
            XCTAssertEqual(events.values.last?.message, "Considering the next step")
            XCTAssertEqual(events.values.last?.content, "Step \(expectedStep) of 12")
            let message: DevelopmentMessage
            switch messages.last?.toolName {
            case "read_file":
                XCTAssertTrue(messages.last!.content.contains("a - b"))
                message = DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(name: "edit_file", arguments: ["path": .string("Sources/Math.swift"), "old_text": .string("a - b"), "new_text": .string("a + b")])])
            case "edit_file":
                message = DevelopmentMessage(role: "assistant", content: "All tests passed.")
            default:
                message = DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Sources/Math.swift")])])
            }
            return try JSONEncoder().encode(DevelopmentWireReply(message: message))
        }
        let result = try await DevelopmentAgent(client: client(), workspace: workspace).run(goal: "Fix addition", model: "qwen3:4b", effort: .quick, onEvent: { events.append($0) }, approveCommand: { _ in false })
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "public func sum(_ a: Int, _ b: Int) -> Int { a + b }\n")
        XCTAssertEqual(result.changedFiles, ["Sources/Math.swift"])
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.finalMessage.contains("has not been verified"))
        XCTAssertFalse(result.finalMessage.contains("All tests passed"))
        XCTAssertTrue(events.values.contains { $0.kind == .fileChanged && $0.path == "Sources/Math.swift" })
        XCTAssertTrue(events.values.contains { $0.kind == .status && $0.content?.contains("12 tool rounds") == true })
        XCTAssertFalse(events.values.filter { $0.kind == .assistant }.contains { $0.content?.contains("All tests passed") == true })
        let started = events.values.filter { $0.kind == .toolStarted }
        XCTAssertEqual(started.map(\.message), ["Reading Sources/Math.swift", "Editing Sources/Math.swift"])
        XCTAssertEqual(started.compactMap(\.path), ["Sources/Math.swift", "Sources/Math.swift"])
        XCTAssertTrue(started.allSatisfy { $0.content == nil }, "Activity summaries must not duplicate source or replacement text")
        XCTAssertTrue(events.values.filter { $0.kind == .toolFinished }.allSatisfy { $0.failure == nil })
    }

    func testToolActivityDescribesValidatedListSearchAndWriteWithoutFileContents() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let catalog = catalog
        let fileContent = "// Activity fixture contents\n"
        DevelopmentURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return catalog }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
            let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
            let reply = messages.last?.role == "tool"
                ? DevelopmentMessage(role: "assistant", content: "Created an activity fixture.")
                : DevelopmentMessage(role: "assistant", toolCalls: [
                    DevelopmentToolCall(name: "list_files", arguments: [:]),
                    DevelopmentToolCall(name: "search", arguments: ["query": .string("Activity fixture")]),
                    DevelopmentToolCall(name: "write_file", arguments: ["path": .string("Sources/Activity.swift"), "content": .string(fileContent)]),
                    DevelopmentToolCall(name: "read_file", arguments: ["path": .string("../Outside.swift")])
                ])
            return try JSONEncoder().encode(DevelopmentWireReply(message: reply))
        }
        let events = DevelopmentEventLog()
        _ = try await DevelopmentAgent(client: client(), workspace: workspace).run(goal: "Create an activity fixture", model: "qwen3-coder:30b", onEvent: { events.append($0) }, approveCommand: { _ in false })
        let started = events.values.filter { $0.kind == .toolStarted }
        XCTAssertEqual(started.map(\.message), ["Listing project files", "Searching the project", "Writing Sources/Activity.swift"])
        XCTAssertEqual(started[1].content, "Activity fixture")
        XCTAssertEqual(started[2].path, "Sources/Activity.swift")
        XCTAssertNil(started[2].content, "File content belongs in the change review rather than the tool-start summary")
        XCTAssertFalse(started.contains { $0.path == "../Outside.swift" }, "Invalid tool arguments must not become activity metadata")
        let failures = events.values.filter { $0.kind == .toolFinished && $0.failure != nil }
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.tool, "read_file")
        XCTAssertEqual(failures.first?.message, "Tool could not complete")
        XCTAssertTrue(failures.first?.failure?.contains("Paths must stay inside") == true)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Sources/Activity.swift"), encoding: .utf8), fileContent)
    }

    func testPlanModeCannotWriteOrRunCommandsEvenIfTheModelRequestsThem() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let catalog = catalog
        let events = DevelopmentEventLog()
        DevelopmentURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return catalog }
            XCTAssertEqual(events.values.last?.message, "Considering the next planning step")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
            let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
            let names = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
            XCTAssertEqual(names, [
                "list_files", "read_file", "search", "request_user_input", "update_plan", "resume_task"
            ])
            let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
            let reply = messages.last?.role == "tool"
                ? DevelopmentMessage(role: "assistant", content: "Plan: inspect the implementation, then add a focused fix.")
                : DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(name: "write_file", arguments: ["path": .string("Sources/Forbidden.swift"), "content": .string("written")]), DevelopmentToolCall(name: "run_command", arguments: ["command": .string("swift test")])])
            return try JSONEncoder().encode(DevelopmentWireReply(message: reply))
        }
        let result = try await DevelopmentAgent(client: client(), workspace: workspace).run(goal: "Plan a change", model: "qwen3-coder:30b", mode: .plan, onEvent: { events.append($0) }, approveCommand: { _ in XCTFail("Plan must never ask to execute a command"); return true })
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/Forbidden.swift").path))
        XCTAssertFalse(events.values.contains { $0.kind == .toolStarted }, "Plan-mode refusals must not appear as started editing or command tools")
        let refusals = events.values.filter { $0.kind == .toolFinished }.compactMap(\.failure)
        XCTAssertEqual(refusals.count, 2)
        XCTAssertTrue(refusals.allSatisfy { $0.contains("Plan mode is read-only") })
    }

    func testDeclinedAndFailedCommandsHaveShortFailureActivity() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let catalog = catalog
        DevelopmentURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return catalog }
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
            let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
            let reply = messages.last?.role == "tool"
                ? DevelopmentMessage(role: "assistant", content: "The first command was declined and the second failed.")
                : DevelopmentMessage(role: "assistant", toolCalls: [
                    DevelopmentToolCall(name: "run_command", arguments: ["command": .string("echo never-run")]),
                    DevelopmentToolCall(name: "run_command", arguments: ["command": .string("/usr/bin/false")])
                ])
            return try JSONEncoder().encode(DevelopmentWireReply(message: reply))
        }
        let events = DevelopmentEventLog()
        let result = try await DevelopmentAgent(client: client(), workspace: workspace).run(goal: "Review the proposed local commands", model: "qwen3-coder:30b", onEvent: { events.append($0) }, approveCommand: { $0.command == "/usr/bin/false" })
        XCTAssertEqual(result.commands.count, 1)
        XCTAssertEqual(events.values.filter { $0.kind == .commandStarted }.compactMap(\.command), ["/usr/bin/false"])
        let failures = events.values.filter { $0.kind == .toolFinished }.compactMap(\.failure)
        XCTAssertEqual(failures.count, 2)
        XCTAssertEqual(failures.first, "You declined this command. No command was run.")
        XCTAssertFalse(failures.contains { $0.contains("never-run") }, "Failure summaries must not duplicate arbitrary command text or output")
        let command = try XCTUnwrap(result.commands.first)
        try VyronProtectedCommandTestSupport.requireExecutionAvailable(command)
        XCTAssertEqual(command.exitCode, 1, "Command output: \(command.output)")
        XCTAssertEqual(failures, ["You declined this command. No command was run.", "The command exited with status 1."])
    }

    func testAgentManualSelectionReachesExactlyTheSelectedCompatibleModel() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try DevelopmentWorkspace(rootURL: root)
        DevelopmentURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" {
                return Data(#"{"models":[{"name":"qwen3.8:27b","size":18000000000,"capabilities":["completion","tools","thinking"]},{"name":"devstral-small-2:24b","size":15000000000,"capabilities":["completion","tools"]}]}"#.utf8)
            }
            XCTAssertEqual(request.url?.path, "/api/chat")
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "devstral-small-2:24b")
            XCTAssertNil(body["think"])
            let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
            XCTAssertFalse(messages[0].content.contains("Native tool formatting:"), "Devstral must not inherit Qwen's native XML grammar")
            return try JSONEncoder().encode(DevelopmentWireReply(message: DevelopmentMessage(role: "assistant", content: "Plan: inspect the project conventions before editing.")))
        }
        let result = try await DevelopmentAgent(client: client(), workspace: workspace).run(goal: "Plan the next change", model: "devstral-small-2:24b", automaticModelSelection: false, mode: .plan, onEvent: { _ in }, approveCommand: { _ in false })
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertEqual(result.steps, 1)
    }

    func testNewQwenFamiliesDiscoverThinkingAndStayWithin32KWithoutCoderXML() async throws {
        for tag in ["qwen3.8:27b", "qwen3.6:35b"] {
            DevelopmentURLProtocol.state.set { request in
                switch request.url?.path {
                case "/api/tags": return try JSONSerialization.data(withJSONObject: ["models": [["name": tag, "size": 18_000_000_000]]])
                case "/api/show": return Data(#"{"capabilities":["completion","tools","thinking"],"thinking":{"values":[false,true],"default":true}}"#.utf8)
                default:
                    XCTAssertEqual(request.url?.path, "/api/chat")
                    let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
                    XCTAssertEqual(body["model"] as? String, tag)
                    XCTAssertNil(body["think"])
                    XCTAssertLessThanOrEqual((body["options"] as? [String: Any])?["num_ctx"] as? Int ?? 0, 32_768)
                    let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
                    XCTAssertFalse(messages[0].content.contains("Native tool formatting:"))
                    return try JSONEncoder().encode(DevelopmentWireReply(message: DevelopmentMessage(role: "assistant", content: "Ready to inspect.")))
                }
            }
            _ = try await client().developmentStep(model: tag, messages: [DevelopmentMessage(role: "system", content: "System rules"), DevelopmentMessage(role: "user", content: "Inspect the project")])
        }
    }

    func testManualCustomModelDiscoversToolsFromShowAndUsesItsExactNativeSelection() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("let number = 1\n".utf8).write(to: root.appendingPathComponent("Sources/Number.swift"))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        DevelopmentURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags": return Data(#"{"models":[{"name":"my-local-coder:latest","size":7000000000}]}"#.utf8)
            case "/api/show":
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
                XCTAssertEqual(body["model"] as? String, "my-local-coder:latest")
                return Data(#"{"capabilities":["completion","tools"]}"#.utf8)
            default:
                XCTAssertEqual(request.url?.path, "/api/chat")
                let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: developmentRequestBody(request)) as? [String: Any])
                XCTAssertEqual(body["model"] as? String, "my-local-coder:latest")
                let messages = try JSONDecoder().decode([DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: body["messages"]!))
                let reply = messages.last?.role == "tool"
                    ? DevelopmentMessage(role: "assistant", content: "Plan: preserve the existing number declaration.")
                    : DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Sources/Number.swift")])])
                return try JSONEncoder().encode(DevelopmentWireReply(message: reply))
            }
        }
        let result = try await DevelopmentAgent(client: client(), workspace: workspace).run(goal: "Read Number.swift and plan the next change.", model: "my-local-coder:latest", automaticModelSelection: false, mode: .plan, onEvent: { _ in }, approveCommand: { _ in false })
        XCTAssertEqual(result.steps, 2)
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertTrue(result.commands.isEmpty)
    }

    func testCustomModelWithoutLocalNativeToolsIsRejectedAtSelectionAndTransport() async throws {
        let fixtures = [
            Data(#"{"capabilities":["completion"]}"#.utf8),
            Data(#"{"capabilities":[]}"#.utf8),
            Data(#"{}"#.utf8),
            Data(#"{"capabilities":["completion","tools"],"remote_model":"remote-coder","remote_host":"https://ollama.com"}"#.utf8)
        ]
        for metadata in fixtures {
            DevelopmentURLProtocol.state.set { request in
                if request.url?.path == "/api/tags" { return Data(#"{"models":[{"name":"my-local-coder:latest","size":7000000000}]}"#.utf8) }
                guard request.url?.path == "/api/show" else {
                    XCTFail("Unsupported or remote models must be rejected before the goal reaches chat")
                    throw URLError(.unsupportedURL)
                }
                return metadata
            }
            let local = client()
            do {
                _ = try await local.developmentModel(model: "my-local-coder:latest", automaticModelSelection: false, effort: .balanced)
                XCTFail("Manual selection must reject unsupported metadata without fallback")
            } catch {
                XCTAssertTrue(error is DevelopmentAgentError || (error as? LocalAIError) == .cloudModelNotAllowed)
            }
            do {
                _ = try await local.developmentStep(model: "my-local-coder:latest", messages: [DevelopmentMessage(role: "system", content: "System rules"), DevelopmentMessage(role: "user", content: "Inspect the project")])
                XCTFail("Direct transport must apply the same capability and local-only checks")
            } catch {
                XCTAssertTrue(error is DevelopmentAgentError || (error as? LocalAIError) == .cloudModelNotAllowed)
            }
        }
    }
}
