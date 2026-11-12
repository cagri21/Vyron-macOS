import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronConversationModeTests: XCTestCase {
    func testNewConversationCanChooseChatOrWorkBeforeFirstMessage() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        configure(test)

        XCTAssertFalse(test.model.isConversationModeLocked)
        XCTAssertTrue(test.model.canSelectComposerMode(.agent))
        test.model.selectComposerMode(.agent)
        XCTAssertFalse(test.model.isChatWorkspace)
        XCTAssertTrue(test.model.canSelectComposerMode(.chat))
        test.model.selectComposerMode(.chat)
        XCTAssertTrue(test.model.isChatWorkspace)
        XCTAssertTrue(test.model.messages.isEmpty)
    }

    func testFirstChatMessageLocksModeImmediatelyAndAfterResponseCompletes() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        configure(test)
        test.model.composer.draft = "Explain a simple concept."
        test.model.send()

        XCTAssertTrue(test.model.isConversationModeLocked)
        XCTAssertTrue(test.model.isChatWorkspace)
        XCTAssertFalse(test.model.canSelectComposerMode(.agent))
        test.model.composer.mode = .agent
        XCTAssertEqual(test.model.composer.mode, .chat)

        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        test.model.selectComposerMode(.plan)
        XCTAssertEqual(test.model.composer.mode, .chat)
        XCTAssertEqual(test.model.selectedConversation?.mode, ComposerMode.chat.rawValue)
        XCTAssertEqual(test.model.messages.filter { $0.role == "user" }.count, 1)
    }

    func testRejectedMessageDoesNotLockModeOrDiscardDraft() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        configure(test)
        let prompt = String(repeating: "x", count: VyronConversationLimits.maximumMessageBytes + 1)
        test.model.composer.draft = prompt

        test.model.send()

        XCTAssertFalse(test.model.isConversationModeLocked)
        XCTAssertTrue(test.model.messages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, prompt)
        XCTAssertNotNil(test.model.errorMessage)
        test.model.selectComposerMode(.agent)
        XCTAssertEqual(test.model.composer.mode, .agent)
    }

    func testFirstWorkMessageKeepsChatUnavailableButAllowsAgentAndPlan() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        configure(test)
        test.model.selectComposerMode(.plan)
        test.model.composer.draft = "Plan a small application."
        test.model.send()
        XCTAssertTrue(test.model.isConversationModeLocked)
        test.model.composer.mode = .chat
        XCTAssertEqual(test.model.composer.mode, .plan)
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertFalse(test.model.isChatWorkspace)
        XCTAssertFalse(test.model.canSelectComposerMode(.chat))
        test.model.selectComposerMode(.agent)
        XCTAssertEqual(test.model.composer.mode, .agent)
        test.model.selectComposerMode(.plan)
        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertEqual(test.model.selectedConversation?.mode, ComposerMode.plan.rawValue)
    }

    func testSavedConversationRestoresItsLockedModeAfterRelaunch() async throws {
        for mode in [ComposerMode.chat, .plan] {
            let test = try VyronFeatureTestHarness()
            defer { test.cleanUp() }
            configure(test)
            test.model.selectComposerMode(mode)
            test.model.composer.draft = "Explain the next steps."
            test.model.send()
            try await test.waitUntil { !test.model.foregroundRun.isGenerating }
            let id = try XCTUnwrap(test.model.selectedConversationID)
            let reopened = AppModel(historyDirectory: test.directory)
            defer {
                reopened.cancelModelFeatureVerification()
                reopened.stopGeneration()
            }

            reopened.selectConversation(id)
            XCTAssertTrue(reopened.isConversationModeLocked)
            XCTAssertEqual(reopened.composer.mode, mode)
            reopened.composer.mode = mode == .chat ? .plan : .chat
            XCTAssertEqual(reopened.composer.mode, mode)
            XCTAssertEqual(reopened.selectedConversation?.mode, mode.rawValue)
        }
    }

    func testSelectingDifferentSavedConversationRestoresItsOwnMode() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        var chat = Conversation(title: "Chat", workspacePath: nil)
        chat.mode = ComposerMode.chat.rawValue
        chat.messages = [ChatMessage(role: "user", content: "Hello")]
        var work = Conversation(title: "Work", workspacePath: nil)
        work.mode = ComposerMode.plan.rawValue
        work.messages = [ChatMessage(role: "user", content: "Plan this")]
        test.model.conversations = [chat, work]

        test.model.selectConversation(chat.id)
        XCTAssertEqual(test.model.composer.mode, .chat)
        test.model.selectConversation(work.id)
        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertTrue(test.model.isConversationModeLocked)
        test.model.selectConversation(chat.id)
        XCTAssertEqual(test.model.composer.mode, .chat)
        XCTAssertTrue(test.model.isConversationModeLocked)
    }

    func testLegacyHistoryWithoutRecognizedModeRetainsExistingWorkFallback() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        for mode in [nil, "Unknown legacy mode"] as [String?] {
            var conversation = Conversation(title: "Legacy", workspacePath: nil)
            conversation.mode = mode
            conversation.messages = [ChatMessage(role: "user", content: "Existing request")]
            test.model.conversations.append(conversation)

            test.model.selectConversation(conversation.id)
            XCTAssertEqual(test.model.composer.mode, .agent)
            XCTAssertTrue(test.model.isConversationModeLocked)
            test.model.composer.mode = .chat
            XCTAssertEqual(test.model.composer.mode, .agent)
            XCTAssertEqual(test.model.selectedConversation?.mode, mode)
        }
    }

    func testStartingNewConversationRestoresModeChoiceAndPreservesOldChat() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        configure(test)
        test.model.composer.draft = "Explain a simple concept."
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let original = try XCTUnwrap(test.model.selectedConversation)

        test.model.newConversation()

        XCTAssertFalse(test.model.isConversationModeLocked)
        XCTAssertNil(test.model.selectedConversationID)
        XCTAssertTrue(test.model.messages.isEmpty)
        test.model.selectComposerMode(.chat)
        XCTAssertEqual(test.model.composer.mode, .chat)
        test.model.selectComposerMode(.agent)
        XCTAssertEqual(test.model.composer.mode, .agent)
        XCTAssertEqual(test.model.conversations.first?.id, original.id)
        XCTAssertEqual(test.model.conversations.first?.mode, original.mode)
        XCTAssertEqual(test.model.conversations.first?.messages.map(\.id), original.messages.map(\.id))
    }

    private func configure(_ test: VyronFeatureTestHarness) {
        test.select(test.profile(), provider: test.provider, capabilities: ["tools"])
        test.model.computerWork.automaticRequestRouting = false
    }
}
