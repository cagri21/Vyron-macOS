import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronSideChatCommandTests: XCTestCase {
    func testBareCommandOpensAnEmptyTemporaryChatAndKeepsCompletedTurnsOutOfHistory() async throws {
        let harness = try VyronSideChatTestHarness()
        addTeardownBlock { await harness.cleanUp() }
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let historyURL = harness.directory.appendingPathComponent("conversations.json")
        let originalHistory = try Data(contentsOf: historyURL)
        let originalOrganization = model.sidebarState.sidebarOrganization

        model.composer.draft = "/side"
        XCTAssertTrue(model.canSubmitSideChatCommand)
        let sideID = try XCTUnwrap(model.submitComposer())
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        XCTAssertFalse(session.isGenerating)
        XCTAssertTrue(session.draft.isEmpty)
        XCTAssertEqual(model.composer.draft, "")
        XCTAssertEqual(model.selectedConversationID, sourceID)
        XCTAssertEqual(model.conversations.map(\.id), [sourceID])
        XCTAssertEqual(model.sidebarState.sidebarOrganization, originalOrganization)
        XCTAssertFalse(model.canOpenSideChatInMain(sideID))

        session.draft = "Explain the original task."
        session.send()
        try await harness.waitUntil { await harness.provider.requests.count == 1 }
        await harness.provider.complete(1, answer: "Temporary answer")
        try await harness.waitUntil { !session.isGenerating }
        XCTAssertEqual(model.sideChatConversation(with: sideID)?.messages.last?.content, "Temporary answer")
        XCTAssertEqual(model.sideChatConversation(with: sideID)?.messages.last?.activity?.state, .completed)
        XCTAssertEqual(try Data(contentsOf: historyURL), originalHistory)
        let reopened = AppModel(historyDirectory: harness.directory)
        XCTAssertEqual(reopened.conversations.map(\.id), [sourceID])

        model.closeSideChatWindow(sideID)
        XCTAssertNil(model.newSideChatSessions[sideID])
        XCTAssertNil(model.sideChatConversation(with: sideID))
    }

    func testInlineQuestionStartsSeparatelyWhileParentKeepsItsRunningTurnAndQueue() async throws {
        let harness = try VyronSideChatTestHarness()
        addTeardownBlock { await harness.cleanUp() }
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        model.composer.draft = "Keep working on the main task."
        model.send()
        try await harness.waitUntil { await harness.provider.requests.count == 1 }
        let parentResponse = try XCTUnwrap(model.foregroundRun.activeResponse)
        model.composer.queueMessages = true
        model.composer.draft = "Answer this next in the parent chat."
        model.send()
        let originalQueue = model.queuedMessages.map(\.id)
        XCTAssertEqual(originalQueue.count, 1)
        let transcriptIDs = model.messages.map(\.id)
        let attachment = VyronImageAttachment(name: "Draft.png", mimeType: "image/png", data: Data([1, 2, 3]))
        model.composerAttachments.screenshotDraft.images = [attachment]

        model.composer.draft = "  /side\nWhat evidence do we already have?  "
        XCTAssertTrue(model.canSubmitSideChatCommand)
        let sideID = try XCTUnwrap(model.submitSideChatCommand())
        try await harness.waitUntil { await harness.provider.requests.count == 2 }
        let requests = await harness.provider.requests
        XCTAssertTrue(requests[1].messages.contains {
            $0.content.contains("Keep the original task and its evidence intact.")
        })
        XCTAssertTrue(requests[1].messages.last?.content.hasPrefix("What evidence do we already have?") == true)
        XCTAssertEqual(
            model.sideChatConversation(with: sideID)?.messages.first?.content,
            "What evidence do we already have?"
        )
        XCTAssertTrue(requests[1].messages.allSatisfy { ($0.images ?? []).isEmpty })
        XCTAssertEqual(model.selectedConversationID, sourceID)
        XCTAssertEqual(model.messages.map(\.id), transcriptIDs)
        XCTAssertEqual(model.queuedMessages.map(\.id), originalQueue)
        XCTAssertEqual(model.foregroundRun.activeResponse, parentResponse)
        XCTAssertTrue(model.foregroundRun.isGenerating)
        XCTAssertEqual(model.composer.draft, "")
        XCTAssertEqual(model.composerAttachments.screenshotDraft.images, [attachment])

        let responseID = try XCTUnwrap(model.newSideChatSessions[sideID]?.activeResponse?.messageID)
        await harness.provider.emit("Partial side answer", request: 2)
        try await harness.waitUntil {
            model.sideChatConversation(with: sideID)?.messages.last?.content == "Partial side answer"
        }
        XCTAssertTrue(model.isResponseActivityLive(conversationID: sideID, messageID: responseID))
        model.closeSideChatWindow(sideID)
        await harness.provider.emit("Late side token", request: 2)
        await harness.provider.complete(2, answer: "Late side answer")
        XCTAssertNil(model.sideChatConversation(with: sideID))
        XCTAssertFalse(model.isResponseActivityLive(conversationID: sideID, messageID: responseID))
        XCTAssertEqual(model.foregroundRun.activeResponse, parentResponse)
        XCTAssertTrue(model.foregroundRun.isGenerating)
        XCTAssertEqual(model.queuedMessages.map(\.id), originalQueue)
    }

    func testCommandRejectsMissingSourceAndIgnoresNonCommandTextWithoutClearingDraft() async throws {
        let harness = try VyronSideChatTestHarness()
        addTeardownBlock { await harness.cleanUp() }
        let model = harness.model
        for text in ["Explain /side in this sentence.", "/sideways", "/side/example", "`/side`"] {
            model.composer.draft = text
            XCTAssertFalse(model.canSubmitSideChatCommand)
            XCTAssertNil(model.submitSideChatCommand())
            XCTAssertEqual(model.composer.draft, text)
        }

        model.selectedConversationID = nil
        model.composer.draft = "/side Preserve this question"
        XCTAssertFalse(model.canSubmitSideChatCommand)
        XCTAssertNil(model.submitComposer())
        XCTAssertEqual(model.composer.draft, "/side Preserve this question")
        XCTAssertTrue(model.newSideChatSessions.isEmpty)
    }

    func testTemporaryChatsCanRunIndependentlyAndRetryAfterProviderFailure() async throws {
        let harness = try VyronSideChatTestHarness()
        addTeardownBlock { await harness.cleanUp() }
        let model = harness.model
        model.composer.draft = "/side First side question"
        let firstID = try XCTUnwrap(model.submitSideChatCommand())
        try await harness.waitUntil { await harness.provider.requests.count == 1 }
        let first = try XCTUnwrap(model.newSideChatSessions[firstID])
        model.composer.draft = "/side Second side question"
        let secondID = try XCTUnwrap(model.submitSideChatCommand())
        try await harness.waitUntil { await harness.provider.requests.count == 2 }
        let second = try XCTUnwrap(model.newSideChatSessions[secondID])
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertFalse(model.canCreateTemporarySideChat(from: firstID))

        await harness.provider.fail(1)
        try await harness.waitUntil { !first.isGenerating }
        XCTAssertNotNil(first.errorMessage)
        XCTAssertEqual(model.sideChatConversation(with: firstID)?.messages.last?.activity?.state, .failed)
        XCTAssertTrue(second.isGenerating)

        first.draft = "Retry the first question."
        first.send()
        try await harness.waitUntil { await harness.provider.requests.count == 3 }
        await harness.provider.complete(3, answer: "First answer")
        try await harness.waitUntil { !first.isGenerating }
        XCTAssertNil(first.errorMessage)
        XCTAssertEqual(model.sideChatConversation(with: firstID)?.messages.last?.content, "First answer")

        model.closeSideChatWindow(secondID)
        XCTAssertFalse(second.isGenerating)
        XCTAssertFalse(second.canSend)
        await harness.provider.emit("Stale token", request: 2)
        await harness.provider.complete(2, answer: "Stale second answer")
        XCTAssertNil(model.sideChatConversation(with: secondID))
        XCTAssertEqual(model.sideChatConversation(with: firstID)?.messages.last?.content, "First answer")
    }
}
