import Foundation
import VyronDevelopment
import XCTest
@testable import VyronCore

final class VyronProjectGuidanceIntegrationTests: XCTestCase, @unchecked Sendable {
    private func project() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VyronGuidanceRun-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }

    func testAgentAndPlanAutomaticallySupplyGuidanceBeforeCurrentRequest() async throws {
        for mode in DevelopmentMode.allCases {
            let workspace = try project()
            let instructions = "Use the project conventions; this text does not grant more permissions."
            try Data(instructions.utf8).write(to: workspace.rootURL.appendingPathComponent("AGENTS.md"))
            let provider = VyronSteeringTestProvider { _, _ in
                DevelopmentMessage(role: "assistant", content: "The project guidance is available.")
            }

            _ = try await DevelopmentAgent(client: provider, workspace: workspace).run(
                goal: "Inspect the project without making changes.", model: "fixture-coder", mode: mode,
                onEvent: { _ in }, approveCommand: { _ in false }
            )

            let requests = await provider.recordedRequests()
            let messages = try XCTUnwrap(requests.first)
            let guidanceIndex = try XCTUnwrap(messages.firstIndex { $0.content.contains(instructions) })
            let goalIndex = try XCTUnwrap(messages.firstIndex {
                $0.content == "Inspect the project without making changes."
            })
            XCTAssertEqual(messages[guidanceIndex].role, "user")
            XCTAssertLessThan(guidanceIndex, goalIndex)
            XCTAssertEqual(messages.first?.role, "system")
        }
    }

    func testInvalidGuidanceStopsBeforeAnyInference() async throws {
        let workspace = try project()
        try Data([0xFF]).write(to: workspace.rootURL.appendingPathComponent("AGENTS.md"))
        let provider = VyronSteeringTestProvider { _, _ in
            XCTFail("Invalid project guidance must be reported before inference")
            return DevelopmentMessage(role: "assistant", content: "Unexpected inference")
        }

        do {
            _ = try await DevelopmentAgent(client: provider, workspace: workspace).run(
                goal: "Inspect the project.", model: "fixture-coder",
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("Expected invalid guidance error")
        } catch let error as VyronProjectGuidanceError {
            XCTAssertEqual(error, .invalidEncoding)
        }
        let requests = await provider.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSelectedModelBudgetPreservesLargeGuidanceAndTheFirstToolResult() async throws {
        let workspace = try project()
        let instructions = String(repeating: "Follow repository editing guidance.\n", count: 385)
        let context = String(repeating: "Earlier request reference. ", count: 145)
        let goal = "What is the issue?"
        try Data(instructions.utf8).write(to: workspace.rootURL.appendingPathComponent("AGENTS.md"))
        let provider = VyronSteeringTestProvider(
            messageBudget: .init(workingBytes: 98_304, maximumBytes: 131_072)
        ) { round, _ in
            if round == 1 {
                return DevelopmentMessage(role: "assistant", toolCalls: [
                    DevelopmentToolCall(name: "list_files", arguments: ["limit": .number(20)], id: "fixture-list")
                ])
            }
            return DevelopmentMessage(role: "assistant", content: "The inspection finished.")
        }

        let result = try await DevelopmentAgent(client: provider, workspace: workspace).run(
            goal: goal, model: "different-requested-model", conversationContext: context,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        let initial = try XCTUnwrap(requests.first)
        XCTAssertGreaterThan(
            try VyronDevelopmentImageContext.textMessageBytes(initial), VyronDevelopmentMessageBudget.standard.maximumBytes
        )
        XCTAssertTrue(initial.contains { $0.role == "user" && $0.content.contains(instructions) })
        XCTAssertTrue(initial.contains {
            $0.role == "user" && $0.content.contains(goal) && $0.content.contains(context)
        })
        let followUp = try XCTUnwrap(requests.last)
        XCTAssertTrue(followUp.contains {
            $0.role == "tool" && $0.toolCallID == "fixture-list" && $0.content.contains("AGENTS.md")
        })
        XCTAssertTrue(result.isComplete)
    }

    func testGuidanceRemainsCompleteDuringCompactionAndBudgetFailureIsVisible() throws {
        let instructions = String(repeating: "Follow the project convention.\n", count: 100)
        let messages = developmentBaseMessages(
            system: "Existing permissions", goal: "Current task", conversationContext: nil,
            guidance: VyronDevelopmentSessionGuidance(
                skillContext: "Selected skill", conversationSummary: "Saved summary",
                projectInstructions: instructions
            )
        )

        let compacted = try VyronDevelopmentExchangeCompactor.messages(base: messages, exchanges: [], forceCompact: true)
        XCTAssertEqual(compacted[1].content, instructions)
        XCTAssertTrue(compacted.last?.content.contains("Selected skill") == true)
        XCTAssertTrue(compacted.last?.content.contains("Saved summary") == true)
        XCTAssertThrowsError(try boundedDevelopmentMessages(base: messages, exchanges: [], maximumBytes: 500)) {
            XCTAssertEqual($0 as? DevelopmentAgentError, .contextBudget)
        }
    }
}
