import Foundation
import XCTest
import VyronAutomation
import VyronCore
@testable import Vyron

@MainActor
final class VyronConversationModeIntegrationTests: XCTestCase {
    func testScreenshotImportKeepsExistingWorkConversationAndDraft() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let conversation = selectWorkConversation(test.model)
        test.model.composer.draft = "Preserve this draft."

        XCTAssertTrue(test.model.canAttachScreenshots)
        test.model.attachCapturedScreenshot(try VyronScreenshotTestImage.jpeg(), name: "Screen.jpg")
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.isLoading)
        try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }

        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertEqual(test.model.selectedConversationID, conversation.id)
        XCTAssertEqual(test.model.composer.draft, "Preserve this draft.")
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images.map(\.name), ["Screen.jpg"])
        XCTAssertEqual(test.model.messages.map(\.id), conversation.messages.map(\.id))
        XCTAssertFalse(test.model.composerAttachments.screenshotDraft.isLoading)
        XCTAssertNil(test.model.composerAttachments.screenshotImportTask)
    }

    func testLiveVoiceCannotConvertExistingWorkConversation() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider, capabilities: ["tools"])
        let conversation = selectWorkConversation(test.model)

        XCTAssertNotNil(test.model.validateVoiceStart(live: true))
        XCTAssertFalse(test.model.sendVoiceTurn("Start a spoken conversation."))
        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertEqual(test.model.selectedConversationID, conversation.id)
        XCTAssertEqual(test.model.messages.map(\.id), conversation.messages.map(\.id))
        XCTAssertFalse(test.model.voice.isActive)
    }

    func testChatHelperSelectionCannotConvertExistingWorkConversation() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider, capabilities: ["tools"])
        let conversation = selectWorkConversation(test.model)
        test.model.modelSelection.models.append(LocalModel(name: "chat-helper", size: 1))
        let selectedModel = test.model.modelSelection.selectedModel
        let profiles = test.model.modelSelection.connectionProfiles
        let automaticallySelect = test.model.modelSelection.automaticModelSelection

        test.model.useLocalModel("chat-helper", forChat: true)

        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertEqual(test.model.selectedConversationID, conversation.id)
        XCTAssertEqual(test.model.selectedConversation?.mode, ComposerMode.plan.rawValue)
        XCTAssertEqual(test.model.messages.map(\.id), conversation.messages.map(\.id))
        XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
        XCTAssertEqual(test.model.modelSelection.connectionProfiles, profiles)
        XCTAssertEqual(test.model.modelSelection.automaticModelSelection, automaticallySelect)
    }

    func testDiscussingSnapshotStartsFreshChatAndPreservesExistingWork() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let original = selectWorkConversation(test.model)
        let snapshot = AutomationSnapshot(
            applicationName: "Example App", applicationID: "example.app", text: "Read-only window text"
        )

        test.model.discussSnapshot(snapshot)

        XCTAssertEqual(test.model.composer.mode, .chat)
        XCTAssertNil(test.model.selectedConversationID)
        XCTAssertFalse(test.model.isConversationModeLocked)
        XCTAssertTrue(test.model.composer.draft.contains(snapshot.text))
        XCTAssertEqual(test.model.conversations.first?.id, original.id)
        XCTAssertEqual(test.model.conversations.first?.mode, original.mode)
        XCTAssertEqual(test.model.conversations.first?.messages.map(\.id), original.messages.map(\.id))
    }

    private func selectWorkConversation(_ model: AppModel) -> Conversation {
        var conversation = Conversation(title: "Existing work", workspacePath: nil)
        conversation.mode = ComposerMode.plan.rawValue
        conversation.messages = [ChatMessage(role: "user", content: "Plan a small application.")]
        model.conversations.append(conversation)
        model.selectConversation(conversation.id)
        return conversation
    }
}
