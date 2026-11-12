import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronBackgroundChatLifecycleTests: XCTestCase {
    func testLeavingBeforeInferenceStartsKeepsOriginalProvider() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Original question")
        let originalID = try XCTUnwrap(test.model.selectedConversationID)
        test.model.newConversation()
        let secondProvider = VyronQueueTestProvider()
        test.model.modelSelection.configuredInferenceClient = secondProvider
        test.model.selectComposerMode(.chat)
        test.send("New question")
        let secondID = try XCTUnwrap(test.model.selectedConversationID)

        try await waitUntil {
            let originalCount = await test.provider.requests.count
            let secondCount = await secondProvider.requests.count
            return originalCount == 1 && secondCount == 1
        }
        let original = await test.provider.requests.first?.last?.content
        let second = await secondProvider.requests.first?.last?.content
        XCTAssertEqual(original, "Original question")
        XCTAssertEqual(second, "New question")
        await test.provider.complete(0, answer: "Original provider's answer")
        await secondProvider.complete(0, answer: "New provider's answer")
        try await waitUntil {
            !test.model.isSidebarConversationActive(originalID) && !test.model.isSidebarConversationActive(secondID)
        }
        XCTAssertEqual(
            test.model.conversations.first { $0.id == originalID }?.messages.last?.content,
            "Original provider's answer"
        )
        XCTAssertEqual(test.model.messages.last?.content, "New provider's answer")
    }

    func testBackgroundFailureStaysInItsChatAndCanBeRetried() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        test.model.computerWork.automaticRequestRouting = false
        test.send("First question")
        try await waitUntil { await test.provider.requests.count == 1 }
        let firstID = try XCTUnwrap(test.model.selectedConversationID)
        test.model.newConversation()
        test.model.selectComposerMode(.chat)
        test.send("Second question")
        try await waitUntil { await test.provider.requests.count == 2 }
        let secondID = try XCTUnwrap(test.model.selectedConversationID)

        await test.provider.fail(0)
        try await waitUntil { !test.model.isSidebarConversationActive(firstID) }
        let failed = test.model.conversations.first { $0.id == firstID }?.messages.last
        XCTAssertEqual(failed?.activity?.state, .failed)
        XCTAssertNotNil(failed?.activity?.entries.last?.detail)
        XCTAssertEqual(test.model.selectedConversationID, secondID)
        XCTAssertTrue(test.model.isSidebarConversationActive(secondID))
        XCTAssertNil(test.model.errorMessage)

        test.model.selectConversation(firstID)
        test.send("Try the first question again")
        try await waitUntil { await test.provider.requests.count == 3 }
        let retry = await test.provider.requests[2]
        XCTAssertTrue(retry.contains { $0.content == "First question" })
        XCTAssertEqual(retry.last?.content, "Try the first question again")
        await test.provider.complete(2, answer: "First answer after retry")
        await test.provider.complete(1, answer: "Second answer")
        try await waitUntil {
            !test.model.isSidebarConversationActive(firstID) && !test.model.isSidebarConversationActive(secondID)
        }
        XCTAssertEqual(test.model.messages.last?.content, "First answer after retry")
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    func testShutdownCancelsAndSavesSelectedAndBackgroundReplies() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Background question")
        try await waitUntil { test.model.messages.last?.content == "Partial answer 0" }
        let firstID = try XCTUnwrap(test.model.selectedConversationID)
        test.model.newConversation()
        test.model.selectComposerMode(.chat)
        test.send("Selected question")
        try await waitUntil { test.model.messages.last?.content == "Partial answer 1" }
        let secondID = try XCTUnwrap(test.model.selectedConversationID)

        await test.model.shutdownAsync()
        let cancellations = await test.provider.cancellations
        XCTAssertEqual(cancellations, 2)
        let history = try Data(contentsOf: test.directory.appendingPathComponent("conversations.json"))
        let saved = try JSONDecoder().decode([Conversation].self, from: history)
        let first = saved.first { $0.id == firstID }?.messages.last
        let second = saved.first { $0.id == secondID }?.messages.last
        XCTAssertEqual(first?.activity?.state, .stopped)
        XCTAssertEqual(first?.content, "Partial answer 0")
        XCTAssertEqual(second?.activity?.state, .stopped)
        XCTAssertEqual(second?.content, "Partial answer 1")
    }

    private func cleanUp(_ test: VyronQueueTestHarness) {
        for id in test.model.conversations.map(\.id) where test.model.isSidebarConversationActive(id) {
            test.model.selectConversation(id)
            test.model.stopGeneration()
        }
        test.cleanUp()
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Chat replies did not reach their expected state")
        throw CancellationError()
    }
}
