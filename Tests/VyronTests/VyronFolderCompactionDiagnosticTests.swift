import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronFolderCompactionDiagnosticTests: XCTestCase {
    func testTraceExistingWorkCompactionBoundaryWithoutFolderAttachments() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "Project notes".write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        await test.model.loadWorkspace(project)
        var conversation = Conversation(title: "Original work task", workspacePath: project.path)
        conversation.projectPath = test.model.sidebarActiveProjectPath
        conversation.mode = ComposerMode.agent.rawValue
        conversation.messages = [
            ChatMessage(role: "user", content: "Inspect the existing project."),
            ChatMessage(role: "assistant", content: String(repeating: "OLD_WORK_DETAILS ", count: 300))
        ]
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id
        test.model.composer.mode = .agent
        print("DIAGNOSTIC after setup: " + state(test.model))
        test.send("/compact")
        let summaryStarted = await waitUntil { await test.provider.requests.count == 1 }
        guard summaryStarted else { return XCTFail("Summary never started: " + state(test.model)) }
        let summary = "Verified project progress. " + String(repeating: "Keep this constraint. ", count: 220)
            + "Final retained constraint."
        await test.provider.complete(0, answer: summary)
        let summaryFinished = await waitUntil { !test.model.foregroundRun.isGenerating }
        guard summaryFinished else { return XCTFail("Summary never finished: " + state(test.model)) }
        print("DIAGNOSTIC after summary: " + state(test.model))
        test.model.composer.draft = "Inspect README.md and explain the next step."
        print("DIAGNOSTIC before followup: " + state(test.model))
        test.model.send()
        let agentStarted = await waitUntil { await test.provider.developmentRequests.count == 1 }
        guard agentStarted else { return XCTFail("Agent never started: " + state(test.model)) }
        await test.provider.completeDevelopment(0, message: DevelopmentMessage(
            role: "assistant", content: "The README contains project notes. No files changed."
        ))
        let agentFinished = await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertTrue(agentFinished, "Agent never finished: " + state(test.model))
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<500 {
            if await condition() { return true }
            do { try await Task.sleep(for: .milliseconds(5)) } catch { return false }
        }
        return false
    }

    private func state(_ model: AppModel) -> String {
        let details = [
            "canSend=\(model.canSend)",
            "canAccept=\(model.canAcceptConversationMessage)",
            "generating=\(model.foregroundRun.isGenerating)",
            "loading=\(model.composerAttachments.isImporting)",
            "hasAttachments=\(model.composerAttachments.hasDrafts)",
            "folderCount=\(model.composerAttachments.folderAttachmentDraft.folders.count)",
            "bound=\(model.chatSchedulingWorkspaceMatches)",
            "attachedSource=\(model.selectedProjectSourceFolderIsAttached)",
            "mode=\(model.composer.mode)",
            "connected=\(model.modelSelection.isConnected)",
            "available=\(model.modelSelection.modelIsAvailable)",
            "error=\(model.errorMessage ?? "none")",
            "last=\(model.messages.last?.content ?? "none")"
        ]
        return details.joined(separator: ", ")
    }
}
