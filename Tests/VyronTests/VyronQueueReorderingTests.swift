import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronQueueReorderingTests: XCTestCase {
    func testMovingDownUsesOriginalTargetIndexAndPreservesMessageIdentityAndOtherState() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let conversationID = prepare(test.model, contents: ["A", "B", "C", "D"])
        let original = test.model.queuedMessages
        let updatedAt = test.model.selectedConversation?.updatedAt
        test.model.composer.pendingSteeringIDs = [original[1].id]

        XCTAssertTrue(test.model.moveQueuedMessage(original[0].id, to: original[2].id, conversationID: conversationID))

        XCTAssertEqual(test.model.queuedMessages, [original[1], original[2], original[0], original[3]])
        XCTAssertEqual(test.model.selectedConversation?.updatedAt, updatedAt)
        XCTAssertEqual(test.model.selectedConversationID, conversationID)
        XCTAssertEqual(test.model.composer.draft, "An unsent draft")
        XCTAssertEqual(test.model.composer.pendingSteeringIDs, [original[1].id])
        XCTAssertTrue(test.model.composer.queueMessages)
        XCTAssertTrue(test.model.messages.isEmpty)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
    }

    func testMovingUpPlacesMessageBeforeOriginalTarget() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let conversationID = prepare(test.model, contents: ["A", "B", "C", "D"])
        let original = test.model.queuedMessages

        XCTAssertTrue(test.model.moveQueuedMessage(original[3].id, to: original[1].id, conversationID: conversationID))

        XCTAssertEqual(test.model.queuedMessages, [original[0], original[3], original[1], original[2]])
    }

    func testReorderedQueuePersistsAndReopensWithoutSending() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let conversationID = prepare(test.model, contents: ["First", "Second", "Third"])
        let original = test.model.queuedMessages
        XCTAssertTrue(test.model.moveQueuedMessage(original[2].id, to: original[0].id, conversationID: conversationID))
        let expected = test.model.queuedMessages

        let reopened = AppModel(historyDirectory: test.directory)
        defer {
            reopened.stopGeneration()
            reopened.scheduledTasks.shutdown()
        }
        reopened.selectConversation(conversationID)

        XCTAssertEqual(reopened.queuedMessages, expected)
        XCTAssertFalse(reopened.foregroundRun.isGenerating)
        XCTAssertTrue(reopened.messages.isEmpty)
    }

    func testCrossConversationDeletedAndUnknownDragIdentitiesCannotMoveMessages() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let conversationID = prepare(test.model, contents: ["A", "B", "C"])
        let original = test.model.queuedMessages
        var other = Conversation(title: "Other chat", workspacePath: nil)
        other.queuedMessages = [VyronQueuedMessage(content: "Other A"), VyronQueuedMessage(content: "Other B")]
        test.model.conversations.append(other)
        test.model.selectedConversationID = other.id
        let otherQueue = test.model.queuedMessages

        XCTAssertFalse(test.model.moveQueuedMessage(original[0].id, to: original[1].id, conversationID: conversationID))
        XCTAssertEqual(test.model.queuedMessages, otherQueue)
        XCTAssertEqual(test.model.conversations.first { $0.id == conversationID }?.queuedMessages, original)
        test.model.selectedConversationID = conversationID
        test.model.deleteQueuedMessage(original[0].id)
        let afterDeletion = test.model.queuedMessages
        XCTAssertFalse(test.model.moveQueuedMessage(original[0].id, to: original[1].id, conversationID: conversationID))
        XCTAssertFalse(test.model.moveQueuedMessage(original[1].id, to: original[0].id, conversationID: conversationID))
        XCTAssertFalse(test.model.moveQueuedMessage(UUID(), to: original[1].id, conversationID: conversationID))
        XCTAssertFalse(test.model.moveQueuedMessage(original[1].id, to: UUID(), conversationID: conversationID))
        XCTAssertFalse(test.model.moveQueuedMessage(original[1].id, to: original[1].id, conversationID: conversationID))
        XCTAssertEqual(test.model.queuedMessages, afterDeletion)
        XCTAssertEqual(test.model.composer.draft, "An unsent draft")
    }

    func testPendingSteeringAndQueueEditingRejectMovesWithoutChangingTheirState() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let conversationID = prepare(test.model, contents: ["A", "B", "C"])
        let original = test.model.queuedMessages
        test.model.composer.pendingSteeringIDs = [original[0].id]
        XCTAssertFalse(test.model.canReorderQueuedMessage(original[0].id))
        XCTAssertFalse(test.model.moveQueuedMessage(original[0].id, to: original[1].id, conversationID: conversationID))
        test.model.composer.pendingSteeringIDs = [original[1].id]
        XCTAssertTrue(test.model.canReorderQueuedMessage(original[0].id))
        XCTAssertFalse(test.model.moveQueuedMessage(original[0].id, to: original[1].id, conversationID: conversationID))
        XCTAssertEqual(test.model.composer.pendingSteeringIDs, [original[1].id])
        test.model.composer.pendingSteeringIDs = []
        test.model.editQueuedMessage(original[0].id)
        XCTAssertFalse(test.model.canReorderQueuedMessage(original[1].id))
        XCTAssertFalse(test.model.moveQueuedMessage(original[1].id, to: original[2].id, conversationID: conversationID))
        XCTAssertEqual(test.model.queuedMessages, original)
        XCTAssertEqual(test.model.composer.editingQueuedMessageID, original[0].id)
        XCTAssertEqual(test.model.composer.draft, "A")
        test.model.composer.cancelQueuedMessageEdit()
        XCTAssertEqual(test.model.composer.draft, "An unsent draft")
    }

    func testUnavailableLifecycleStatesAndSingleMessageQueuesRejectReordering() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let conversationID = prepare(test.model, contents: ["A", "B"])
        let original = test.model.queuedMessages
        test.model.isShuttingDown = true
        XCTAssertFalse(test.model.canReorderQueuedMessage(original[0].id))
        XCTAssertFalse(test.model.moveQueuedMessage(original[0].id, to: original[1].id, conversationID: conversationID))
        test.model.isShuttingDown = false
        let response = test.model.beginTestForegroundResponse()
        test.model.foregroundRun.start(response) {}
        test.model.foregroundRun.beginDevelopment(response)
        XCTAssertTrue(test.model.foregroundRun.stop())
        XCTAssertFalse(test.model.canReorderQueuedMessage(original[0].id))
        try await waitUntil { !test.model.foregroundRun.isStoppingDevelopment }
        test.model.computerWork.isComputerWorkActive = true
        XCTAssertFalse(test.model.canReorderQueuedMessage(original[0].id))
        test.model.computerWork.isComputerWorkActive = false
        test.model.isRunningScheduledTask = true
        XCTAssertFalse(test.model.canReorderQueuedMessage(original[0].id))
        test.model.isRunningScheduledTask = false
        XCTAssertEqual(test.model.queuedMessages, original)
        test.model.selectedConversationID = nil
        XCTAssertFalse(test.model.canReorderQueuedMessage(original[0].id))
        _ = prepare(test.model, contents: ["Only message"])
        XCTAssertFalse(test.model.canReorderQueuedMessage(test.model.queuedMessages[0].id))
    }

    func testFailedHistorySaveRestoresQueueOrderAndPreservesDraft() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let conversationID = prepare(test.model, contents: ["A", "B", "C"])
        let original = test.model.queuedMessages
        let history = test.directory.appendingPathComponent("conversations.json")
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)

        XCTAssertFalse(test.model.moveQueuedMessage(original[0].id, to: original[2].id, conversationID: conversationID))

        XCTAssertEqual(test.model.queuedMessages, original)
        XCTAssertEqual(test.model.composer.draft, "An unsent draft")
        XCTAssertNotNil(test.model.errorMessage)
    }

    func testAutomaticDrainFollowsReorderedQueueAndRejectsAnAlreadyDrainedDrag() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Original task")
        try await waitUntil { await test.provider.requests.count == 1 }
        let conversationID = try XCTUnwrap(test.model.selectedConversationID)
        test.send("A")
        test.send("B")
        test.send("C")
        let original = test.model.queuedMessages
        XCTAssertTrue(test.model.moveQueuedMessage(original[2].id, to: original[0].id, conversationID: conversationID))
        test.model.composer.draft = "Preserve this unsent draft"

        await test.provider.complete(0, answer: "Original answer")
        try await waitUntil { await test.provider.requests.count == 2 }
        let firstFollowUp = await test.provider.requests[1]
        XCTAssertEqual(firstFollowUp.last?.content, "C")
        XCTAssertFalse(test.model.moveQueuedMessage(original[2].id, to: original[0].id, conversationID: conversationID))
        XCTAssertTrue(test.model.moveQueuedMessage(original[0].id, to: original[1].id, conversationID: conversationID))
        await test.provider.complete(1, answer: "C answer")
        try await waitUntil { await test.provider.requests.count == 3 }
        let secondFollowUp = await test.provider.requests[2]
        XCTAssertEqual(secondFollowUp.last?.content, "B")
        await test.provider.complete(2, answer: "B answer")
        try await waitUntil { await test.provider.requests.count == 4 }
        let thirdFollowUp = await test.provider.requests[3]
        XCTAssertEqual(thirdFollowUp.last?.content, "A")
        await test.provider.complete(3, answer: "A answer")
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, "Preserve this unsent draft")
        XCTAssertEqual(test.model.messages.filter { $0.role == "user" }.map(\.content), ["Original task", "C", "B", "A"])
    }

    private func prepare(_ model: AppModel, contents: [String]) -> UUID {
        var conversation = Conversation(title: "Queued task", workspacePath: nil)
        conversation.mode = ComposerMode.chat.rawValue
        conversation.queuedMessages = contents.map { VyronQueuedMessage(content: $0) }
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.composer.draft = "An unsent draft"
        XCTAssertTrue(model.saveHistory())
        return conversation.id
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The queued-message reorder operation did not reach its expected state.")
        throw CancellationError()
    }
}
