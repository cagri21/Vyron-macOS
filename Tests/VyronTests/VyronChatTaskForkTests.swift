import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore
@testable import Vyron

@MainActor
final class VyronChatTaskForkTests: XCTestCase {
    func testWorkThroughChatForkRetainsUnfinishedTaskEvidenceAndOriginalConversation() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let workspace = try workspace(in: test.directory)
        let original = conversation(workspace: workspace)
        let originalTask = try saveTask(conversation: original, workspace: workspace)
        test.model.conversations = [original]
        test.model.selectedConversationID = original.id
        test.model.composer.mode = .agent
        test.model.workspaceState.workspaceURL = workspace.rootURL
        test.model.workspaceState.developmentWorkspaces[workspace.rootURL.path] = workspace
        test.model.registerSidebarConversation(original.id)
        XCTAssertTrue(test.model.saveHistory())

        let chatID = try XCTUnwrap(test.model.continueChat(original.id, in: .chat))
        try await waitUntil { !test.model.workspaceState.isLoadingWorkspace }
        let chat = try XCTUnwrap(test.model.selectedConversation)
        XCTAssertEqual(chat.mode, ComposerMode.chat.rawValue)
        XCTAssertEqual(chat.workspacePath, original.workspacePath)
        XCTAssertEqual(chat.projectPath, original.projectPath)
        let chatTask = try checkpoint(for: chat, workspace: workspace)
        XCTAssertEqual(chatTask.progress.integrations, originalTask.progress.integrations)
        XCTAssertEqual(chatTask.plan, originalTask.plan)
        XCTAssertEqual(chatTask.status, .interrupted)

        let workID = try XCTUnwrap(test.model.continueChat(chatID, in: .agent))
        try await waitUntil { !test.model.workspaceState.isLoadingWorkspace }
        let work = try XCTUnwrap(test.model.selectedConversation)
        let workTask = try checkpoint(for: work, workspace: workspace)
        XCTAssertEqual(work.id, workID)
        XCTAssertEqual(work.mode, ComposerMode.agent.rawValue)
        XCTAssertEqual(workTask.identity.originalGoal, originalTask.identity.originalGoal)
        XCTAssertEqual(workTask.plan, originalTask.plan)
        XCTAssertEqual(workTask.progress.files, originalTask.progress.files)
        XCTAssertEqual(workTask.progress.checks, originalTask.progress.checks)
        XCTAssertEqual(workTask.progress.integrations, originalTask.progress.integrations)
        XCTAssertEqual(try checkpoint(for: original, workspace: workspace), originalTask)
        XCTAssertEqual(test.model.conversations.first { $0.id == original.id }?.messages, original.messages)
        XCTAssertEqual(test.model.conversations.first { $0.id == original.id }?.mode, original.mode)
        XCTAssertEqual(test.model.conversations.count, 3)
    }

    func testCorruptTaskOrHistoryFailureDoesNotLeaveForkCheckpointOrChangeSource() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let workspace = try workspace(in: test.directory)
        let original = conversation(workspace: workspace)
        let sourceTask = try saveTask(conversation: original, workspace: workspace)
        test.model.conversations = [original]
        test.model.selectedConversationID = original.id
        test.model.workspaceState.workspaceURL = workspace.rootURL
        test.model.workspaceState.developmentWorkspaces[workspace.rootURL.path] = workspace
        test.model.registerSidebarConversation(original.id)
        XCTAssertTrue(test.model.saveHistory())
        let organization = test.model.sidebarState.sidebarOrganization
        let history = test.directory.appendingPathComponent("conversations.json")
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)

        XCTAssertNil(test.model.continueChat(original.id, in: .chat))
        XCTAssertEqual(test.model.conversations.count, 1)
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(try checkpoint(for: original, workspace: workspace), sourceTask)
        let checkpointFiles = FileManager.default.enumerator(atPath: workspace.taskStateDirectoryURL.path)?
            .allObjects.compactMap { $0 as? String }.filter { $0.hasSuffix(".json") }
        XCTAssertEqual(checkpointFiles?.count, 1)

        try FileManager.default.removeItem(at: history)
        XCTAssertTrue(test.model.saveHistory())
        let historyData = try Data(contentsOf: history)
        let sourceURL = workspace.taskStateDirectoryURL.appendingPathComponent(original.id.uuidString)
            .appendingPathComponent(sourceTask.identity.id.uuidString + ".json")
        try Data("corrupt checkpoint fixture".utf8).write(to: sourceURL)
        XCTAssertNil(test.model.continueChat(original.id, in: .agent))
        XCTAssertEqual(test.model.selectedConversationID, original.id)
        XCTAssertEqual(test.model.conversations.count, 1)
        XCTAssertEqual(try Data(contentsOf: history), historyData)
        XCTAssertEqual(try String(contentsOf: sourceURL), "corrupt checkpoint fixture")
    }

    func testProjectForkRequiresLoadedWorkspaceInsteadOfSilentlyDiscardingTaskEvidence() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let workspace = try workspace(in: test.directory)
        let original = conversation(workspace: workspace)
        _ = try saveTask(conversation: original, workspace: workspace)
        test.model.conversations = [original]
        test.model.selectedConversationID = original.id
        XCTAssertFalse(test.model.canContinueChat(original.id))
        XCTAssertNil(test.model.continueChat(original.id, in: .chat))
        XCTAssertEqual(test.model.conversations.count, 1)
        XCTAssertEqual(test.model.selectedConversationID, original.id)
        XCTAssertNotNil(test.model.errorMessage)
    }

    private func conversation(workspace: DevelopmentWorkspace) -> Conversation {
        var conversation = Conversation(title: "Template app", workspacePath: workspace.rootURL.path)
        conversation.projectPath = workspace.rootURL.path
        conversation.mode = ComposerMode.agent.rawValue
        conversation.messages = [
            ChatMessage(role: "user", content: "Build and validate the template app."),
            ChatMessage(role: "assistant", content: "The initial project files are ready.")
        ]
        return conversation
    }

    private func saveTask(
        conversation: Conversation,
        workspace: DevelopmentWorkspace
    ) throws -> VyronDevelopmentTaskState {
        var state = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: try XCTUnwrap(conversation.messages.last?.id),
            projectPath: workspace.rootURL.path,
            originalGoal: conversation.messages[0].content
        ))
        try state.updatePlan(VyronDevelopmentPlanUpdate(steps: [
            VyronDevelopmentPlanStep(title: "Create the project", status: .completed),
            VyronDevelopmentPlanStep(title: "Validate it", status: .pending)
        ]))
        try state.recordFile(VyronDevelopmentFileProgress(
            path: "Main.swift", contentHash: VyronDevelopmentFileProgress.hash(content: "struct Main {}")
        ))
        try state.recordCheck(VyronDevelopmentCheckProgress(
            command: "swift test", result: VyronDevelopmentCheckResult(exitCode: 0, timedOut: false)
        ))
        try state.recordIntegration(VyronDevelopmentIntegrationProgress(
            identity: VyronDevelopmentIntegrationIdentity(
                toolName: "mcp_fixture_create", argumentsHash: String(repeating: "a", count: 64)
            ), status: .started, summary: "Creation may have completed; verify before repeating."
        ))
        state.finish(.failed)
        try store(conversation: conversation, workspace: workspace).save(state)
        return state
    }

    private func checkpoint(
        for conversation: Conversation,
        workspace: DevelopmentWorkspace
    ) throws -> VyronDevelopmentTaskState {
        let id = try XCTUnwrap(conversation.messages.last?.id)
        return try XCTUnwrap(store(conversation: conversation, workspace: workspace).load(id: id))
    }

    private func store(
        conversation: Conversation,
        workspace: DevelopmentWorkspace
    ) throws -> VyronDevelopmentTaskStore {
        try VyronDevelopmentTaskStore(
            directoryURL: workspace.taskStateDirectoryURL.appendingPathComponent(conversation.id.uuidString),
            projectPath: workspace.rootURL.path
        )
    }

    private func workspace(in directory: URL) throws -> DevelopmentWorkspace {
        let source = directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let workspace = try DevelopmentWorkspace(rootURL: source)
        let storage = workspace.taskStateDirectoryURL.deletingLastPathComponent()
        addTeardownBlock { try FileManager.default.removeItem(at: storage) }
        return workspace
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The forked workspace did not finish loading.")
        throw CancellationError()
    }
}
