import Foundation
import XCTest
import VyronDevelopment
import VyronModelDomain
@testable import Vyron
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaWorkCatalogBudgetTests: XCTestCase {
    func testSelectedSkillAndFullWorkCatalogRespectAnExplicitContextBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronLocalWorkBudget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        try Data(String(repeating: "Preserve unrelated project files.\n", count: 30).utf8)
            .write(to: directory.appendingPathComponent("AGENTS.md"))
        let external = VyronWebTools.definitions + VyronSkillResourceTools.definitions
            + VyronChatHandoffTools.definitions + [VyronLinkedChatTools.definition] + VyronOfficeTools.definitions
            + VyronMacWorkRun.definitions + VyronChromeTools.definitions
        let supplied = external + [VyronParallelTaskTool.definition] + VyronDevelopmentFileOperationTools.definitions
        let tools = try DevelopmentToolDefinition.available(mode: .agent, externalTools: supplied)
        let provider = VyronWorkBudgetTestProvider(budget: .init(workingBytes: 120_000, maximumBytes: 124_000))
        let agent = DevelopmentAgent(
            client: provider, workspace: try DevelopmentWorkspace(rootURL: directory), onSubagentEvent: { _ in }
        )
        try await agent.configureCommandApproval(.fullAccess)
        try await agent.configureFileOperationAccess(.init(approve: { _ in false }))
        try await agent.configureSession(.init(
            conversationID: UUID(), responseID: UUID(), guidance: .init(
                skillContext: String(repeating: "Complete the requested release using established commands.\n", count: 150)
            )
        ))
        _ = try await agent.run(
            goal: "Build the latest app DMG from the named local app project and update its established website download.",
            model: "qwen3-coder:30b", automaticModelSelection: false, effort: .ultra,
            conversationContext: String(repeating: "Prior release request and observed project context. ", count: 85),
            externalTools: external, onEvent: { _ in }, approveCommand: { _ in false }
        )
        let messages = await provider.messages
        let bytes = try VyronDevelopmentImageContext.estimatedMessageBytes(messages)
        let toolBytes = try JSONEncoder().encode(tools).count
        let request = VyronDevelopmentBudgetRequest(
            model: .init(name: "qwen3-coder:30b", size: 19_000_000_000),
            configuration: .init(effort: .ultra, mode: .agent, externalTools: supplied), minimumMessageBytes: bytes
        )
        let required = bytes + toolBytes + 2_048 + AgentEffort.ultra.developmentBudget.outputTokens
        print("Full Work budget: messageBytes=\(bytes), toolBytes=\(toolBytes), required=\(required)")
        XCTAssertThrowsError(try VyronOllamaDevelopmentBudget.allocation(
            for: request, settings: .init(contextTokens: 65_536), maximumContext: 262_144, toolBytes: toolBytes
        )) { XCTAssertEqual($0 as? DevelopmentAgentError, .contextBudget) }
        let allocation = try VyronOllamaDevelopmentBudget.allocation(
            for: request, settings: .init(contextTokens: 131_072), maximumContext: 262_144, toolBytes: toolBytes
        )
        XCTAssertEqual(allocation.contextTokens, 131_072)
        XCTAssertEqual(allocation.outputTokens, 12_288)
        let wireMessages = try VyronDevelopmentRequestBudget.messages(
            developmentMessagesWithToolProtocol(messages, model: "qwen3-coder:30b"), tools: tools,
            budget: .init(contextTokens: allocation.contextTokens, outputTokens: allocation.outputTokens,
                          maximumMessageBytes: allocation.messageBudget.maximumBytes)
        )
        XCTAssertEqual(wireMessages.count, messages.count)
    }
}
