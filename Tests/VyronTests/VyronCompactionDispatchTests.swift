import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronCompactionDispatchTests: XCTestCase {
    func testCompactUsesCapturedModelAndEffortPreservesTranscriptAndReducesNextRequest() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let original = seedHistory(test.model)
        let model = test.model.modelSelection.selectedModel
        test.model.computerWork.automaticRequestRouting = true
        test.model.modelSelection.automaticModelSelection = true
        test.model.composer.effort = .deep
        test.model.composer.draft = "/compact focus on the current task and verification"
        test.model.send()
        test.model.composer.effort = .ultra
        try await test.waitUntil { await test.provider.requests.count == 1 }
        let captured = await test.provider.effortRequests
        XCTAssertEqual(captured.first?.model, model)
        XCTAssertEqual(captured.first?.configuration.effort, .deep)
        XCTAssertEqual(captured.first?.configuration.systemPrompt, VyronConversationCompactionContext.summarySystemPrompt)
        XCTAssertTrue(captured.first?.messages.last?.content.contains("focus on the current task") == true)
        XCTAssertTrue(captured.flatMap(\.messages).allSatisfy { ($0.images ?? []).isEmpty })
        await test.provider.complete(1, answer: "Goal: maintain the settings feature. Verified: local checks passed.")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let snapshot = try XCTUnwrap(test.model.selectedConversation?.compaction)
        XCTAssertEqual(snapshot.throughMessageID, test.model.messages.last?.id)
        XCTAssertEqual(Array(test.model.messages.prefix(original.count)), original)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        let saved = try JSONDecoder().decode([Conversation].self, from: Data(
            contentsOf: test.directory.appendingPathComponent("conversations.json")
        ))
        XCTAssertEqual(saved.first?.compaction, snapshot)
        test.model.modelSelection.automaticModelSelection = false
        test.model.composer.draft = "What should I do next?"
        test.model.send()
        try await test.waitUntil { await test.provider.requests.count == 2 }
        let requests = await test.provider.requests
        let next = requests[1].messages
        XCTAssertTrue(next.contains { $0.content.contains(snapshot.summary) })
        XCTAssertEqual(next.last?.content, "What should I do next?")
        XCTAssertFalse(next.contains { $0.content.contains("OLD_ASSISTANT_DETAIL") })
        XCTAssertFalse(next.contains { $0.content.hasPrefix("/compact") })
        XCTAssertLessThan(next.reduce(0) { $0 + $1.content.utf8.count }, original.reduce(0) { $0 + $1.content.utf8.count })
        XCTAssertEqual(Array(test.model.messages.prefix(original.count)), original)
        await test.provider.complete(2, answer: "Continue the current task.")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testStoppedCompactionCannotApplyLateSummaryToANewerTurn() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let original = seedHistory(test.model)
        test.model.composer.draft = "/compact"
        test.model.send()
        try await test.waitUntil { await test.provider.requests.count == 1 }
        test.model.stopGeneration()
        test.model.composer.draft = "Use the original history."
        test.model.send()
        try await test.waitUntil { await test.provider.requests.count == 2 }
        await test.provider.complete(1, answer: "STALE_COMPACTION")
        let requests = await test.provider.requests
        XCTAssertTrue(requests[1].messages.contains { $0.content.contains("OLD_ASSISTANT_DETAIL") })
        XCTAssertFalse(requests[1].messages.contains { $0.content.hasPrefix("/compact") })
        XCTAssertNil(test.model.selectedConversation?.compaction)
        XCTAssertEqual(Array(test.model.messages.prefix(original.count)), original)
        await test.provider.complete(2, answer: "Current answer")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertNil(test.model.selectedConversation?.compaction)
        XCTAssertEqual(test.model.messages.last?.content, "Current answer")
    }

    func testInvalidSummaryRetainsPreviousSnapshotAndRetryUsesActualUserIntent() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let original = seedHistory(test.model)
        let previous = VyronConversationCompaction(summary: "Prior task memory", throughMessageID: original[0].id)
        test.model.conversations[0].compaction = previous
        for answer in ["   ", String(repeating: "x", count: 6_001)] {
            test.model.composer.draft = "/compact"
            test.model.send()
            let expected = answer.trimmingCharacters(in: .whitespaces).isEmpty ? 1 : 2
            try await test.waitUntil { await test.provider.requests.count == expected }
            await test.provider.complete(expected, answer: answer)
            try await test.waitUntil { !test.model.foregroundRun.isGenerating }
            XCTAssertEqual(test.model.selectedConversation?.compaction, previous)
            XCTAssertEqual(test.model.errorMessage, VyronCompactionText.invalidSummary)
            XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        }
        test.model.composer.draft = "/compact"
        test.model.send()
        try await test.waitUntil { await test.provider.requests.count == 3 }
        let requests = await test.provider.requests
        XCTAssertFalse(requests[2].messages.contains { $0.content.contains("Message 1 (user):\n/compact") })
        XCTAssertTrue(requests[2].messages.contains { $0.content.contains("Prior task memory") })
        await test.provider.complete(3, answer: "Updated task memory")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.selectedConversation?.compaction?.summary, "Updated task memory")
    }

    func testCompactionSaveFailureKeepsPreviousSnapshotAndDraft() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let original = seedHistory(test.model)
        let previous = VyronConversationCompaction(summary: "Previous memory", throughMessageID: original[0].id)
        test.model.conversations[0].compaction = previous
        try test.makeHistoryUnwritable()
        test.model.composer.draft = "/compact"
        test.model.send()
        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.composer.draft, "/compact")
        XCTAssertEqual(test.model.messages, original)
        XCTAssertEqual(test.model.selectedConversation?.compaction, previous)
    }

    func testSaveFailureAfterInferenceRollsBackSnapshot() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let original = seedHistory(test.model)
        let previous = VyronConversationCompaction(summary: "Previous memory", throughMessageID: original[0].id)
        test.model.conversations[0].compaction = previous
        test.model.composer.draft = "/compact"
        test.model.send()
        try await test.waitUntil { await test.provider.requests.count == 1 }
        try test.makeHistoryUnwritable()
        await test.provider.complete(1, answer: "Unsaved replacement memory")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.selectedConversation?.compaction, previous)
        XCTAssertEqual(Array(test.model.messages.prefix(original.count)), original)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        XCTAssertEqual(test.model.messages.last?.content, VyronCompactionText.failed)
    }

    private func seedHistory(_ model: AppModel) -> [ChatMessage] {
        let messages = [
            ChatMessage(role: "user", content: "Maintain the settings feature and preserve its tests."),
            ChatMessage(role: "assistant", content: String(repeating: "OLD_ASSISTANT_DETAIL ", count: 350)),
            ChatMessage(role: "user", content: "Keep the latest verified progress and next steps."),
            ChatMessage(role: "assistant", content: "Local checks passed. The next step is reviewing settings.")
        ]
        model.conversations[0].messages = messages
        return messages
    }
}
