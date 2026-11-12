import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronOllamaDevelopmentRepairIntegrationTests: XCTestCase {
    override func tearDown() {
        VyronOllamaDevelopmentRepairURLProtocol.state.reset()
        super.tearDown()
    }

    func testEmptyReplyRepairCannotReplayCompletedExternalAction() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronOllamaRepairIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let workspace = try DevelopmentWorkspace(rootURL: directory)
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let original = DevelopmentToolCall(name: "mcp_fixture_create", arguments: [:], id: "created-once")
        let repeated = DevelopmentToolCall(name: "mcp_fixture_create", arguments: [:], id: "repaired-replay")
        let first = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", toolCalls: [original])
        )
        let empty = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant"), thinking: "PRIVATE_REPAIR_THINKING"
        )
        let retry = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", toolCalls: [repeated])
        )
        let final = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "The existing fixture resource is ready.")
        )
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { attempt, _ in
            switch attempt {
            case 1: first
            case 2: empty
            case 3: retry
            default: final
            }
        }
        let calls = VyronSteeringTestLog<DevelopmentToolCall>()
        let agent = DevelopmentAgent(client: try VyronOllamaDevelopmentRepairFixture.client(), workspace: workspace)
        try await agent.configureSession(session)
        let tool = DevelopmentExternalTool(
            name: "mcp_fixture_create", description: "Create one fixture resource",
            inputSchema: ["type": .string("object")], isReadOnly: false
        )

        let result = try await agent.run(
            goal: "Create exactly one fixture resource and report its identity.",
            model: VyronOllamaDevelopmentRepairFixture.model,
            automaticModelSelection: false,
            externalTools: [tool],
            executeExternalTool: { call in
                calls.append(call)
                return DevelopmentExternalResult(text: "Created resource CREATED_RESOURCE_EXACT_42.")
            },
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        XCTAssertEqual(calls.values, [original])
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.finalMessage.contains("existing fixture resource"))
        let requests = VyronOllamaDevelopmentRepairURLProtocol.state.requests
        XCTAssertEqual(requests.count, 4)
        let repairedContext = try VyronOllamaDevelopmentRepairFixture.messages(in: requests[2])
        XCTAssertTrue(repairedContext.contains { $0.content.contains("CREATED_RESOURCE_EXACT_42") })
        let nextContext = try VyronOllamaDevelopmentRepairFixture.messages(in: requests[3])
        XCTAssertTrue(nextContext.contains { $0.content.contains("not executed again") })
        XCTAssertTrue(requests.allSatisfy {
            !String(decoding: $0, as: UTF8.self).contains("PRIVATE_REPAIR_THINKING")
        })
        let store = try VyronDevelopmentTaskStore(
            directoryURL: workspace.taskStateDirectoryURL.appendingPathComponent(session.conversationID.uuidString),
            projectPath: workspace.rootURL.path
        )
        let saved = try XCTUnwrap(store.load(id: session.responseID))
        XCTAssertEqual(saved.progress.integrations.count, 1)
        XCTAssertTrue(saved.progress.integrations.first?.summary.contains("CREATED_RESOURCE_EXACT_42") == true)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self).contains("PRIVATE_REPAIR_THINKING"))
    }
}
