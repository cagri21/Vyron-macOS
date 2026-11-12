import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore
@testable import VyronModelData

private actor MCPAgentProvider: ModelProvider {
    struct Request: Sendable {
        let messages: [DevelopmentMessage]
        let mode: DevelopmentMode
        let tools: [DevelopmentExternalTool]
    }

    private var replies: [DevelopmentMessage]
    private var requests: [Request] = []

    init(replies: [DevelopmentMessage]) { self.replies = replies }

    func models() async throws -> [LocalModel] { [.init(name: "fixture-coder", size: 1)] }
    func chat(model: String, messages: [ChatMessage], systemPrompt: String?, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        throw ModelProviderError.unsupportedTools
    }
    func developmentModel(model: String, automaticModelSelection: Bool, effort: AgentEffort) async throws -> LocalModel {
        .init(name: "fixture-coder", size: 1, capabilities: ["tools"])
    }
    func developmentStep(model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode, externalTools: [])
    }
    func developmentStep(model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode, externalTools: [DevelopmentExternalTool]) async throws -> DevelopmentStep {
        requests.append(.init(messages: messages, mode: mode, tools: externalTools))
        guard !replies.isEmpty else { throw ModelProviderError.invalidResponse("The test requested an unexpected extra model round.") }
        return .init(message: replies.removeFirst())
    }
    func recordedRequests() -> [Request] { requests }
}

private actor MCPAgentExecutor {
    private var calls: [DevelopmentToolCall] = []
    private let result: DevelopmentExternalResult
    private let cancel: Bool

    init(text: String = "Design has 12 components.", isError: Bool = false, cancel: Bool = false) {
        result = .init(text: text, isError: isError)
        self.cancel = cancel
    }
    func execute(_ call: DevelopmentToolCall) throws -> DevelopmentExternalResult {
        calls.append(call)
        if cancel { throw CancellationError() }
        return result
    }
    func recordedCalls() -> [DevelopmentToolCall] { calls }
}

private final class MCPAgentEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DevelopmentEvent] = []
    func append(_ event: DevelopmentEvent) { lock.withLock { events.append(event) } }
    var values: [DevelopmentEvent] { lock.withLock { events } }
}

final class MCPAgentIntegrationTests: XCTestCase, @unchecked Sendable {
    private func workspace() throws -> DevelopmentWorkspace {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VyronMCPAgent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try DevelopmentWorkspace(rootURL: url)
    }

    private func tool(_ name: String = "mcp_penpot_0", readOnly: Bool = true) -> DevelopmentExternalTool {
        .init(name: name, description: "Penpot / inspect design", inputSchema: [
            "type": .string("object"),
            "properties": .object(["page": .object(["type": .string("string")])]),
            "required": .array([.string("page")]),
            "additionalProperties": .bool(false)
        ], isReadOnly: readOnly)
    }

    private func reply(_ call: DevelopmentToolCall) -> DevelopmentMessage {
        .init(role: "assistant", toolCalls: [call])
    }

    func testExternalNativeCallUsesItsBoundExecutorAndRetainsToolCallID() async throws {
        let call = DevelopmentToolCall(name: "mcp_penpot_0", arguments: ["page": .string("Checkout")], id: "native-call-1")
        let provider = MCPAgentProvider(replies: [reply(call), .init(role: "assistant", content: "The design contains 12 components.")])
        let executor = MCPAgentExecutor()
        let events = MCPAgentEvents()
        let result = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Inspect the Checkout design", model: "requested-auto-model", externalTools: [tool()],
            executeExternalTool: { try await executor.execute($0) },
            onEvent: { events.append($0) }, approveCommand: { _ in XCTFail("No command should run"); return false }
        )
        let calls = await executor.recordedCalls()
        let requests = await provider.recordedRequests()
        XCTAssertEqual(calls, [call])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].tools, [tool()])
        let toolMessage = try XCTUnwrap(requests[1].messages.last)
        XCTAssertEqual(toolMessage.role, "tool")
        XCTAssertEqual(toolMessage.toolCallID, "native-call-1")
        XCTAssertEqual(toolMessage.toolName, "mcp_penpot_0")
        XCTAssertTrue(toolMessage.content.contains("Design has 12 components."))
        XCTAssertTrue(toolMessage.content.contains("\"ok\":true"))
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertEqual(result.model, "fixture-coder")
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(events.values.filter { $0.kind == .toolStarted }.count, 1)
        XCTAssertEqual(events.values.filter { $0.kind == .toolFinished }.count, 1)
        XCTAssertNil(events.values.first(where: { $0.kind == .toolFinished })?.failure)
    }

    func testPlanDoesNotExposeOrExecuteWriteToolsEvenIfModelRequestsOne() async throws {
        let writeTool = tool("mcp_penpot_write", readOnly: false)
        let call = DevelopmentToolCall(name: writeTool.name, arguments: ["page": .string("Checkout")])
        let provider = MCPAgentProvider(replies: [reply(call), .init(role: "assistant", content: "I can describe the change in a plan.")])
        let executor = MCPAgentExecutor()
        let result = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Plan a design change", model: "fixture-coder", mode: .plan, externalTools: [writeTool],
            executeExternalTool: { try await executor.execute($0) }, onEvent: { _ in }, approveCommand: { _ in false }
        )
        let requests = await provider.recordedRequests()
        let calls = await executor.recordedCalls()
        XCTAssertTrue(requests.allSatisfy { $0.tools.isEmpty && $0.mode == .plan })
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(requests[1].messages.last?.content.contains("\"ok\":false") == true)
        XCTAssertTrue(result.changedFiles.isEmpty)
    }

    func testPlanCanExecuteRegisteredReadOnlyTool() async throws {
        let call = DevelopmentToolCall(name: "mcp_penpot_0", arguments: ["page": .string("Checkout")])
        let provider = MCPAgentProvider(replies: [reply(call), .init(role: "assistant", content: "Plan based on the current design.")])
        let executor = MCPAgentExecutor()
        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Inspect design and plan implementation", model: "fixture-coder", mode: .plan, externalTools: [tool()],
            executeExternalTool: { try await executor.execute($0) }, onEvent: { _ in }, approveCommand: { _ in false }
        )
        let calls = await executor.recordedCalls()
        let requests = await provider.recordedRequests()
        XCTAssertEqual(calls, [call])
        XCTAssertEqual(requests.first?.tools, [tool()])
    }

    func testUnknownExternalNameNeverReachesExecutor() async throws {
        let call = DevelopmentToolCall(name: "mcp_other_server_0", arguments: [:])
        let provider = MCPAgentProvider(replies: [reply(call), .init(role: "assistant", content: "The requested tool is unavailable.")])
        let executor = MCPAgentExecutor()
        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Inspect the design", model: "fixture-coder", externalTools: [tool()],
            executeExternalTool: { try await executor.execute($0) }, onEvent: { _ in }, approveCommand: { _ in false }
        )
        let calls = await executor.recordedCalls()
        let requests = await provider.recordedRequests()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(requests[1].messages.last?.content.contains("\"ok\":false") == true)
    }

    func testExternalExecutionFailureIsReportedAsFailureAndOutputIsBounded() async throws {
        let call = DevelopmentToolCall(name: "mcp_penpot_0", arguments: ["page": .string("Checkout")])
        let provider = MCPAgentProvider(replies: [reply(call), .init(role: "assistant", content: "The integration failed.")])
        let executor = MCPAgentExecutor(text: "Not connected. " + String(repeating: "界", count: 30_000), isError: true)
        let events = MCPAgentEvents()
        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Inspect the design", model: "fixture-coder", externalTools: [tool()],
            executeExternalTool: { try await executor.execute($0) }, onEvent: { events.append($0) }, approveCommand: { _ in false }
        )
        let requests = await provider.recordedRequests()
        let message = try XCTUnwrap(requests[1].messages.last)
        XCTAssertLessThanOrEqual(message.content.utf8.count, 12_000)
        let value = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(message.content.utf8))
        XCTAssertEqual(value["ok"], .bool(false))
        XCTAssertEqual(value["truncated"], .bool(true))
        XCTAssertNotNil(events.values.first(where: { $0.kind == .toolFinished })?.failure)
    }

    func testCancellationDuringExternalCallIsPropagatedWithoutRetry() async throws {
        let call = DevelopmentToolCall(name: "mcp_penpot_0", arguments: ["page": .string("Checkout")])
        let provider = MCPAgentProvider(replies: [reply(call)])
        let executor = MCPAgentExecutor(cancel: true)
        do {
            _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
                goal: "Inspect the design", model: "fixture-coder", externalTools: [tool()],
                executeExternalTool: { try await executor.execute($0) }, onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("Cancellation must end the task")
        } catch is CancellationError {
            let calls = await executor.recordedCalls()
            let requests = await provider.recordedRequests()
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testDynamicNativeSchemaPreservesNestedJSONAndPlanFiltersWrites() throws {
        let schema: [String: DevelopmentJSONValue] = [
            "type": .string("object"),
            "properties": .object(["operations": .object([
                "type": .string("array"), "items": .object([
                    "type": .string("object"), "properties": .object(["count": .object(["type": .string("integer"), "minimum": .number(1)])])
                ])
            ])]),
            "required": .array([.string("operations")]), "additionalProperties": .bool(false)
        ]
        let read = DevelopmentExternalTool(name: "mcp_nested", description: "Nested external schema", inputSchema: schema, isReadOnly: true)
        let definitions = try DevelopmentToolDefinition.available(mode: .agent, externalTools: [read])
        let data = try JSONEncoder().encode(try XCTUnwrap(definitions.last))
        let wire = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: data)
        guard case .object(let function) = wire["function"] else { return XCTFail("Missing native function schema") }
        XCTAssertEqual(function["parameters"], .object(schema))
        let plan = try DevelopmentToolDefinition.available(mode: .plan, externalTools: [read, tool("mcp_write", readOnly: false)])
        XCTAssertEqual(plan.map(\.function.name), [
            "list_files", "read_file", "search", "request_user_input", "update_plan", "resume_task", "mcp_nested"
        ])
        XCTAssertThrowsError(try DevelopmentToolDefinition.available(mode: .agent, externalTools: [tool("read_file")]))
        XCTAssertThrowsError(try DevelopmentToolDefinition.available(mode: .agent, externalTools: [tool(), tool()]))
    }
}
