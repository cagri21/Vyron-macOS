import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronPluginsNavigationTests: XCTestCase {
    private let provider = VyronPluginsTestProvider()
    private var temporaryDirectory: URL?

    private func makeModel() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronPluginsNavigationTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let model = AppModel(historyDirectory: directory)
        let connection = ModelConnectionProfile(
            name: "In-memory navigation fixture",
            kind: .openAICompatible,
            endpoint: "https://plugins-navigation.invalid/v1",
            selectedModel: "plugins-navigation-test"
        )
        model.modelSelection.connectionProfiles = [connection]
        model.modelSelection.activeConnectionID = connection.id
        model.modelSelection.configuredInferenceClient = provider
        model.modelSelection.selectedModel = connection.selectedModel
        model.modelSelection.automaticModelSelection = false
        model.computerWork.automaticRequestRouting = false
        model.modelSelection.models = [LocalModel(name: connection.selectedModel, size: 1)]
        model.workspaceState.workspaceURL = nil
        model.composer.mode = .chat
        model.modelSelection.isConnected = true

        addTeardownBlock { @MainActor [provider] in
            model.stopGeneration()
            let transfer = model.modelDownloads.shutdown()
            await transfer?.value
            model.scheduledTasks.shutdown()
            await provider.cancelOutstandingAnswer()
            try FileManager.default.removeItem(at: directory)
        }
        return model
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The in-memory navigation fixture did not reach its expected state.")
        throw CancellationError()
    }

    func testPluginsNavigationKeepsActiveRequestAndPersistsItsCompletion() async throws {
        let model = try makeModel()
        model.composer.draft = "Explain the current design."
        XCTAssertTrue(model.canSend)
        model.send()
        try await waitUntil { await self.provider.answerRequests == 1 }
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let answerID = try XCTUnwrap(model.messages.last?.id)
        let historyURL = try XCTUnwrap(temporaryDirectory).appendingPathComponent("conversations.json")
        let workingHistory = try Data(contentsOf: historyURL)

        model.openPlugins()
        XCTAssertEqual(model.appNavigation.destination, .plugins)
        XCTAssertTrue(model.foregroundRun.isGenerating)
        XCTAssertEqual(model.selectedConversationID, conversationID)
        XCTAssertEqual(model.messages.last?.activity?.state, .working)
        XCTAssertEqual(try Data(contentsOf: historyURL), workingHistory)

        model.returnToWorkspace()
        XCTAssertEqual(model.appNavigation.destination, .workspace)
        XCTAssertTrue(model.foregroundRun.isGenerating)
        model.openPlugins()
        await provider.completeAnswer()
        try await waitUntil { !model.foregroundRun.isGenerating }

        XCTAssertEqual(model.appNavigation.destination, .plugins, "Completing a background answer must preserve the current page.")
        XCTAssertEqual(model.selectedConversationID, conversationID)
        XCTAssertEqual(model.messages.last?.id, answerID)
        XCTAssertEqual(model.messages.last?.content, "The existing request completed after opening Plugins.")
        XCTAssertEqual(model.messages.last?.activity?.state, .completed)
        let cancellations = await provider.answerCancellations
        XCTAssertEqual(cancellations, 0)
        let saved = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: historyURL))
        XCTAssertEqual(saved.first?.id, conversationID)
        XCTAssertEqual(saved.first?.messages.last?.id, answerID)
        XCTAssertEqual(saved.first?.messages.last?.activity?.state, .completed)
        XCTAssertEqual(saved.first?.messages.last?.content, model.messages.last?.content)

        model.returnToWorkspace()
        XCTAssertEqual(model.appNavigation.destination, .workspace)
        XCTAssertEqual(model.messages.last?.id, answerID)
    }

    func testPluginsRoundTripPreservesDraftWorkspaceInspectorAndDownload() async throws {
        let model = try makeModel()
        let workspace = try XCTUnwrap(temporaryDirectory).appendingPathComponent("FixtureProject", isDirectory: true)
        let conversation = Conversation(title: "Existing task", workspacePath: workspace.path)
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.workspaceState.workspaceURL = workspace
        model.composer.draft = "An unfinished request with details."
        model.composerAttachments.attachedFiles = [AttachedFile(path: "README.md", content: "Fixture context")]
        model.inspector.inspectorTab = .changes
        model.inspector.selectedProjectFilePath = "Sources/App.swift"
        model.inspector.projectFilePreview = "Existing preview"
        model.inspector.selectedChangePath = "Sources/Changed.swift"
        model.inspector.terminalOutput = "Existing command output\n[exit 0]"
        model.inspector.showTerminal = true
        model.appNavigation.showWorkspace = false
        model.sidebarState.sidebarSearchText = "Existing task"
        let progress = ModelPullProgress(status: "Downloading", completed: 42, total: 100)
        let transfer = VyronModelTransferFixture.start(in: model.modelDownloads, progress: progress)
        try await waitUntil { model.modelDownloads.progressByTag[transfer.tag] == progress }
        let connections = model.mcpConnections

        model.openPlugins()
        model.returnToWorkspace()

        XCTAssertEqual(model.appNavigation.destination, .workspace)
        XCTAssertEqual(model.selectedConversationID, conversation.id)
        XCTAssertEqual(model.conversations.map(\.id), [conversation.id])
        XCTAssertEqual(model.workspaceState.workspaceURL, workspace)
        XCTAssertEqual(model.composer.draft, "An unfinished request with details.")
        XCTAssertEqual(model.composerAttachments.attachedFiles.map(\.path), ["README.md"])
        XCTAssertEqual(model.composerAttachments.attachedFiles.first?.content, "Fixture context")
        XCTAssertEqual(model.inspector.inspectorTab, .changes)
        XCTAssertEqual(model.inspector.selectedProjectFilePath, "Sources/App.swift")
        XCTAssertEqual(model.inspector.projectFilePreview, "Existing preview")
        XCTAssertEqual(model.inspector.selectedChangePath, "Sources/Changed.swift")
        XCTAssertEqual(model.inspector.terminalOutput, "Existing command output\n[exit 0]")
        XCTAssertTrue(model.inspector.showTerminal)
        XCTAssertFalse(model.appNavigation.showWorkspace)
        XCTAssertEqual(model.sidebarState.sidebarSearchText, "Existing task")
        XCTAssertEqual(model.modelDownloads.active?.tag, transfer.tag)
        XCTAssertEqual(model.modelDownloads.active?.id, transfer.id)
        XCTAssertEqual(model.modelDownloads.progressByTag, [transfer.tag: progress])
        XCTAssertTrue(model.mcpConnections === connections)
    }

    func testSelectingCurrentChatFromPluginsPreservesDraftAndRunningRequest() async throws {
        let model = try makeModel()
        model.composer.draft = "Keep this response running."
        model.send()
        try await waitUntil { await self.provider.answerRequests == 1 }
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let answerID = try XCTUnwrap(model.messages.last?.id)
        model.composer.draft = "My next question is still unfinished."
        model.openPlugins()

        model.selectConversation(conversationID)

        XCTAssertEqual(model.appNavigation.destination, .workspace)
        XCTAssertEqual(model.selectedConversationID, conversationID)
        XCTAssertEqual(model.composer.draft, "My next question is still unfinished.")
        XCTAssertTrue(model.foregroundRun.isGenerating)
        XCTAssertEqual(model.messages.last?.id, answerID)
        XCTAssertEqual(model.messages.last?.activity?.state, .working)
        let cancellations = await provider.answerCancellations
        XCTAssertEqual(cancellations, 0)

        await provider.completeAnswer()
        try await waitUntil { !model.foregroundRun.isGenerating }
        XCTAssertEqual(model.messages.last?.id, answerID)
        XCTAssertEqual(model.messages.last?.activity?.state, .completed)
        XCTAssertEqual(model.composer.draft, "My next question is still unfinished.")
    }

    func testNewTaskFromPluginsReturnsToWorkspaceAndRetainsPreviousHistory() throws {
        let model = try makeModel()
        var conversation = Conversation(title: "Previous task", workspacePath: nil)
        conversation.messages = [ChatMessage(role: "user", content: "Keep this history.")]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.composer.draft = "Discard this draft only because I chose New task."
        model.composerAttachments.attachedFiles = [AttachedFile(path: "Notes.md", content: "Previous attachment")]
        model.openPlugins()

        model.newConversation()

        XCTAssertEqual(model.appNavigation.destination, .workspace)
        XCTAssertNil(model.selectedConversationID)
        XCTAssertEqual(model.composer.draft, "")
        XCTAssertTrue(model.composerAttachments.attachedFiles.isEmpty)
        XCTAssertEqual(model.composer.mode, .agent)
        XCTAssertEqual(model.conversations.first?.id, conversation.id)
        XCTAssertEqual(model.conversations.first?.messages, conversation.messages)
    }
}
