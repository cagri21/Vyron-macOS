import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronCompactionWorkTests: XCTestCase {
    func testWorkCompactUsesSummaryInferenceAndFutureAgentReceivesFullMemory() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "Project notes".write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        await test.model.loadWorkspace(project)
        var conversation = Conversation(title: "Original work task", workspacePath: project.path)
        conversation.projectPath = test.model.sidebarActiveProjectPath
        conversation.mode = ComposerMode.agent.rawValue
        let original = [
            ChatMessage(role: "user", content: "Inspect the existing project."),
            ChatMessage(role: "assistant", content: String(repeating: "OLD_WORK_DETAILS ", count: 300))
        ]
        conversation.messages = original
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id
        test.model.composer.mode = .agent
        test.send("/compact")
        try await waitUntil { await test.provider.requests.count == 1 }
        let initialAgentRequests = await test.provider.developmentRequests
        XCTAssertTrue(initialAgentRequests.isEmpty)
        let summary = "Verified project progress. " + String(repeating: "Keep this constraint. ", count: 220)
            + "Final retained constraint."
        await test.provider.complete(0, answer: summary)
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.composer.mode, .agent)
        XCTAssertEqual(test.model.selectedConversation?.title, "Original work task")
        XCTAssertEqual(Array(test.model.messages.prefix(original.count)), original)
        test.send("Inspect README.md and explain the next step.")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        let agentRequests = await test.provider.developmentRequests
        XCTAssertTrue(agentRequests[0].contains { $0.content.contains(summary) })
        XCTAssertFalse(agentRequests[0].contains { $0.content.contains("OLD_WORK_DETAILS") })
        XCTAssertTrue(agentRequests[0].contains { $0.content.contains("Inspect README.md and explain the next step.") })
        await test.provider.completeDevelopment(0, message: DevelopmentMessage(
            role: "assistant", content: "The README contains project notes. No files changed."
        ))
        try await waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testCompactRemainsAvailableForSavedWorkChatWithoutItsProject() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        var conversation = Conversation(title: "Saved Work", workspacePath: "/Unavailable/Project")
        conversation.mode = ComposerMode.agent.rawValue
        conversation.messages = [
            ChatMessage(role: "user", content: "Review the saved progress."),
            ChatMessage(role: "assistant", content: "The earlier work remains saved.")
        ]
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id
        test.model.composer.mode = .agent
        test.model.workspaceState.workspaceURL = nil
        test.model.composer.draft = "/compact"
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await waitUntil { await test.provider.requests.count == 1 }
        await test.provider.complete(0, answer: "The user wants to review the saved Work progress.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertNotNil(test.model.selectedConversation?.compaction)
        let agentRequests = await test.provider.developmentRequests
        XCTAssertTrue(agentRequests.isEmpty)
        XCTAssertEqual(test.model.selectedConversation?.workspacePath, "/Unavailable/Project")
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Work compaction did not reach the expected boundary.")
        throw CancellationError()
    }
}
