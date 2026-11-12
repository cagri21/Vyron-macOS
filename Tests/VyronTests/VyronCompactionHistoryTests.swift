import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronCompactionHistoryTests: XCTestCase {
    func testLegacyConversationDecodesAndCompactionRoundTripsWithoutChangingMessages() throws {
        var conversation = Conversation(title: "Saved chat", workspacePath: "/Local/Project")
        conversation.messages = [ChatMessage(role: "user", content: "Preserve this original message.")]
        let legacyData = try JSONEncoder().encode(conversation)
        let legacy = try JSONDecoder().decode(Conversation.self, from: legacyData)
        XCTAssertNil(legacy.compaction)
        XCTAssertEqual(legacy.messages, conversation.messages)
        conversation.compaction = VyronConversationCompaction(
            summary: "The user wants the original message preserved.",
            throughMessageID: conversation.messages[0].id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let restored = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(conversation))
        XCTAssertEqual(restored.compaction, conversation.compaction)
        XCTAssertEqual(restored.messages, conversation.messages)
        XCTAssertEqual(restored.workspacePath, "/Local/Project")
        XCTAssertEqual(restored.id, conversation.id)
    }

    func testBoundedHistoryReservesSummaryAndPreservesLatestPromptAndImages() throws {
        let old = ChatMessage(role: "assistant", content: "Covered old detail")
        let summary = String(repeating: "Summary fact. ", count: 400)
        let snapshot = VyronConversationCompaction(summary: summary, throughMessageID: old.id)
        var history = [ChatMessage(role: "user", content: "Original goal"), old]
        for index in 0..<20 {
            history.append(ChatMessage(role: "user", content: "Follow-up \(index) " + String(repeating: "a", count: 500)))
            history.append(ChatMessage(role: "assistant", content: String(repeating: "b", count: 500)))
        }
        let image = VyronImageAttachment(name: "Current.png", mimeType: "image/png", data: Data([1, 2, 3]))
        let latest = ChatMessage(role: "user", content: String(repeating: "最新の指示", count: 500), images: [image])
        history.append(latest)
        let before = history
        let result = VyronConversationRequestContext.boundedHistory(history, context: [:], compaction: snapshot)
        XCTAssertTrue(result.messages.first?.content.contains(summary) == true)
        XCTAssertFalse(result.messages.contains { $0.content == "Covered old detail" })
        XCTAssertEqual(result.messages.last, latest)
        XCTAssertTrue(result.omittedOlderMessages)
        XCTAssertEqual(history, before)
    }

    func testCompactionTurnsDoNotReplaceOriginalTaskLineage() throws {
        let original = ChatMessage(role: "user", content: "Implement the requested feature.")
        let response = ChatMessage(role: "assistant", content: "A verified checkpoint.")
        let compact = ChatMessage(role: "user", content: "/compact keep the current task")
        let confirmation = ChatMessage(role: "assistant", content: "Context compacted.")
        let continued = ChatMessage(role: "user", content: "continue")
        let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(
            for: "continue", messages: [original, response, compact, confirmation, continued]
        ))
        XCTAssertEqual(context.originalGoal, original.content)
        XCTAssertEqual(context.priorResponseIDs, [response.id])
    }

    func testContinueChatCopiesSummaryAndRemapsBoundaryToCopiedTranscript() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let sourceID = try XCTUnwrap(test.model.selectedConversationID)
        test.model.conversations[0].messages += [
            ChatMessage(role: "assistant", content: "Original response"),
            ChatMessage(role: "user", content: "/compact"),
            ChatMessage(role: "assistant", content: "Context compacted.")
        ]
        let boundary = try XCTUnwrap(test.model.messages.last?.id)
        let snapshot = VyronConversationCompaction(summary: "Retain the original task.", throughMessageID: boundary)
        test.model.conversations[0].compaction = snapshot
        let original = test.model.messages
        let copiedID = try XCTUnwrap(test.model.continueChat(sourceID, in: .chat))
        let copied = try XCTUnwrap(test.model.conversations.first { $0.id == copiedID })
        XCTAssertEqual(copied.compaction?.summary, snapshot.summary)
        XCTAssertEqual(copied.compaction?.createdAt, snapshot.createdAt)
        XCTAssertEqual(copied.compaction?.throughMessageID, copied.messages.last?.id)
        XCTAssertNotEqual(copied.compaction?.throughMessageID, boundary)
        XCTAssertEqual(copied.messages.map(\.content), original.map(\.content))
        XCTAssertEqual(test.model.conversations.first { $0.id == sourceID }?.messages, original)
    }

    func testRepeatedCompactWithoutNewMessagesDoesNotCallTheModelAgain() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        test.model.composer.draft = "/compact"
        test.model.send()
        try await test.waitUntil { await test.provider.requests.count == 1 }
        await test.provider.complete(1, answer: "The user wants to preserve the original task.")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let before = test.model.messages
        let snapshot = test.model.selectedConversation?.compaction
        test.model.composer.draft = "/compact"
        test.model.send()
        let requests = await test.provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(test.model.messages, before)
        XCTAssertEqual(test.model.selectedConversation?.compaction, snapshot)
        XCTAssertEqual(test.model.errorMessage, VyronCompactionText.alreadyCompact)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
    }

    func testEmptyChatDoesNotSendCompactToInference() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        test.model.conversations[0].messages = []
        test.model.composer.draft = "/compact"
        test.model.send()
        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(test.model.errorMessage, VyronCompactionText.noHistory)
        XCTAssertTrue(test.model.messages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, "/compact")
    }

    func testExplicitFocusCanRefineAnExistingSummaryWithoutNewMessages() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let boundary = try XCTUnwrap(test.model.messages.last?.id)
        test.model.conversations[0].compaction = VyronConversationCompaction(
            summary: "Keep the task, file paths, and verified results.", throughMessageID: boundary
        )
        test.model.composer.draft = "/compact prioritize the file paths"
        test.model.send()
        try await test.waitUntil { await test.provider.requests.count == 1 }
        let requests = await test.provider.requests
        XCTAssertTrue(requests[0].messages.contains { $0.content.contains("Keep the task, file paths") })
        XCTAssertTrue(requests[0].messages.contains { $0.content.contains("prioritize the file paths") })
        await test.provider.complete(1, answer: "Retained file paths and verified task progress.")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.selectedConversation?.compaction?.summary, "Retained file paths and verified task progress.")
    }
}
