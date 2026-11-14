import Foundation
import XCTest
import VyronLocalization
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronSettingsNavigationTests: XCTestCase {
    func testOpeningSettingsSelectsGeneralOrRequestedSectionWithoutChangingPreferences() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.composer.queueMessages = false
        test.model.modelSelection.builtinModelSettings = ModelSettings(temperature: 0.3)
        test.model.composer.effort = .deep
        let selectedModel = test.model.modelSelection.selectedModel
        let savedLanguage = UserDefaults.standard.string(forKey: VyronLocalizationDefaultsKey.language.rawValue)

        test.model.openSettings(.voice)
        XCTAssertEqual(test.model.appNavigation.destination, .settings)
        XCTAssertEqual(test.model.appNavigation.settingsSection, .voice)

        test.model.openSettings()
        XCTAssertEqual(test.model.appNavigation.settingsSection, .general)

        for section in VyronSettingsSection.allCases {
            test.model.openSettings(section)
            XCTAssertEqual(test.model.appNavigation.destination, .settings)
            XCTAssertEqual(test.model.appNavigation.settingsSection, section)
        }

        XCTAssertFalse(test.model.composer.queueMessages)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: VyronUserDefaultsKey.queueFollowUpMessages.rawValue))
        XCTAssertEqual(test.model.modelSelection.builtinModelSettings, ModelSettings(temperature: 0.3))
        XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
        XCTAssertEqual(test.model.composer.effort, .deep)
        XCTAssertEqual(test.model.composer.mode, .chat)
        XCTAssertEqual(UserDefaults.standard.string(forKey: VyronLocalizationDefaultsKey.language.rawValue), savedLanguage)
    }

    func testSettingsRoundTripPreservesDraftWorkspaceAndConversation() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let workspace = test.directory.appendingPathComponent("ExistingProject", isDirectory: true)
        var conversation = Conversation(title: "Existing task", workspacePath: workspace.path)
        conversation.mode = ComposerMode.plan.rawValue
        conversation.messages = [ChatMessage(role: "user", content: "Keep this conversation.")]
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id
        test.model.workspaceState.workspaceURL = workspace
        test.model.composer.draft = "An unfinished request."
        test.model.composerAttachments.attachedFiles = [AttachedFile(path: "Notes.md", content: "Selected project context")]
        test.model.inspector.inspectorTab = .changes
        test.model.appNavigation.showWorkspace = true
        test.model.inspector.showTerminal = true
        test.model.inspector.terminalOutput = "Existing command output\n[exit 0]"
        let connections = test.model.mcpConnections

        test.model.openSettings(.models)
        test.model.openSettings(.general)
        test.model.appNavigation.settingsSection = .permissions
        XCTAssertEqual(test.model.appNavigation.destination, .settings)
        test.model.returnToWorkspace()

        XCTAssertEqual(test.model.appNavigation.destination, .workspace)
        XCTAssertEqual(test.model.appNavigation.settingsSection, .permissions)
        XCTAssertEqual(test.model.composer.draft, "An unfinished request.")
        XCTAssertEqual(test.model.workspaceState.workspaceURL, workspace)
        XCTAssertEqual(test.model.selectedConversationID, conversation.id)
        XCTAssertEqual(test.model.conversations.map(\.id), [conversation.id])
        XCTAssertEqual(test.model.conversations.first?.messages, conversation.messages)
        XCTAssertEqual(test.model.conversations.first?.mode, ComposerMode.plan.rawValue)
        XCTAssertEqual(test.model.composerAttachments.attachedFiles.map(\.path), ["Notes.md"])
        XCTAssertEqual(test.model.composerAttachments.attachedFiles.first?.content, "Selected project context")
        XCTAssertEqual(test.model.inspector.inspectorTab, .changes)
        XCTAssertTrue(test.model.appNavigation.showWorkspace)
        XCTAssertTrue(test.model.inspector.showTerminal)
        XCTAssertEqual(test.model.inspector.terminalOutput, "Existing command output\n[exit 0]")
        XCTAssertTrue(test.model.mcpConnections === connections)
    }

    func testActiveResponseCompletesWhileSettingsIsOpen() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let profile = ModelConnectionProfile(
            name: "In-memory settings fixture",
            kind: .openAICompatible,
            endpoint: "https://settings-navigation.invalid/v1",
            selectedModel: "queue-test"
        )
        test.model.modelSelection.connectionProfiles = [profile]
        test.model.modelSelection.activeConnectionID = profile.id
        test.send("Keep this request running while I open Settings.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let conversationID = try XCTUnwrap(test.model.selectedConversationID)
        let answerID = try XCTUnwrap(test.model.messages.last?.id)
        test.model.composer.draft = "My next question is unfinished."

        test.model.openSettings(.general)
        test.model.openSettings(.voice)

        XCTAssertEqual(test.model.appNavigation.destination, .settings)
        XCTAssertEqual(test.model.appNavigation.settingsSection, .voice)
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.selectedConversationID, conversationID)
        XCTAssertEqual(test.model.messages.last?.id, answerID)
        XCTAssertEqual(test.model.composer.draft, "My next question is unfinished.")

        await test.provider.complete(0, answer: "The original request completed.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertEqual(test.model.appNavigation.destination, .settings)
        XCTAssertEqual(test.model.appNavigation.settingsSection, .voice)
        XCTAssertEqual(test.model.messages.last?.id, answerID)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        XCTAssertEqual(test.model.messages.last?.content, "The original request completed.")
        let cancellations = await test.provider.cancellations
        XCTAssertEqual(cancellations, 0)

        test.model.returnToWorkspace()
        XCTAssertEqual(test.model.appNavigation.destination, .workspace)
        XCTAssertEqual(test.model.selectedConversationID, conversationID)
        XCTAssertEqual(test.model.messages.last?.id, answerID)
        XCTAssertEqual(test.model.composer.draft, "My next question is unfinished.")
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The in-memory settings fixture did not reach its expected state.")
        throw CancellationError()
    }
}
