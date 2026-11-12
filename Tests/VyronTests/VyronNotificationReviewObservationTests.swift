import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronNotificationReviewObservationTests: XCTestCase {
    func testKnownReviewOwnerAndTimestampDoNotFollowANewerTaskOrRepeatedPublish() throws {
        let test = VyronQueueTestHarness()
        defer {
            clearActiveRun(test.model)
            test.cleanUp()
        }
        let first = workingChat("First owner")
        let second = workingChat("Newer task")
        test.model.conversations = [first, second]
        activate(first, in: test.model)
        let firstResponse = try XCTUnwrap(first.messages.last?.id)
        let requestID = UUID()
        test.model.recordNotificationReview(requestID)
        let initial = try XCTUnwrap(test.model.notifications.reviewObservation)
        XCTAssertEqual(initial.target, .response(VyronNotificationResponseID(
            conversationID: first.id, responseID: firstResponse
        )))

        activate(second, in: test.model)
        test.model.recordNotificationReview(requestID)
        let unchanged = try XCTUnwrap(test.model.notifications.reviewObservation)
        XCTAssertEqual(unchanged.requestID, requestID)
        XCTAssertEqual(unchanged.target, initial.target)
        XCTAssertEqual(unchanged.observedAt, initial.observedAt)

        let replacementID = UUID()
        test.model.recordNotificationReview(replacementID)
        let replacement = try XCTUnwrap(test.model.notifications.reviewObservation)
        XCTAssertEqual(replacement.requestID, replacementID)
        XCTAssertEqual(replacement.target, .response(VyronNotificationResponseID(
            conversationID: second.id, responseID: try XCTUnwrap(second.messages.last?.id)
        )))
        XCTAssertGreaterThanOrEqual(replacement.observedAt, initial.observedAt)
    }

    func testInitiallyUnownedReviewRemainsPluginScopedWhenWorkStarts() throws {
        let test = VyronQueueTestHarness()
        defer {
            clearActiveRun(test.model)
            test.cleanUp()
        }
        let conversation = workingChat("A task that starts later")
        test.model.conversations = [conversation]
        let requestID = UUID()
        test.model.recordNotificationReview(requestID)
        let initial = try XCTUnwrap(test.model.notifications.reviewObservation)
        XCTAssertEqual(initial.target, .plugins)

        activate(conversation, in: test.model)
        XCTAssertEqual(test.model.notificationDevelopmentOwners.count, 1)
        test.model.recordNotificationReview(requestID)
        let repeated = try XCTUnwrap(test.model.notifications.reviewObservation)
        XCTAssertEqual(repeated.target, .plugins)
        XCTAssertEqual(repeated.observedAt, initial.observedAt)
        XCTAssertEqual(repeated.requestID, requestID)
    }

    func testClearingReviewRemovesObservationAndShutdownIgnoresLateEvents() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.recordNotificationReview(UUID())
        XCTAssertNotNil(test.model.notifications.reviewObservation)
        test.model.recordNotificationReview(nil)
        XCTAssertNil(test.model.notifications.reviewObservation)
        let currentID = UUID()
        test.model.recordNotificationReview(currentID)
        let current = try XCTUnwrap(test.model.notifications.reviewObservation)

        test.model.isShuttingDown = true
        test.model.recordNotificationReview(UUID())
        test.model.recordNotificationReview(nil)
        XCTAssertEqual(test.model.notifications.reviewObservation?.requestID, currentID)
        XCTAssertEqual(test.model.notifications.reviewObservation?.target, current.target)
        XCTAssertEqual(test.model.notifications.reviewObservation?.observedAt, current.observedAt)
    }

    private func workingChat(_ title: String) -> Conversation {
        var conversation = Conversation(title: title, workspacePath: nil)
        conversation.messages = [ChatMessage(role: "assistant", content: "", activity: ResponseActivity())]
        return conversation
    }

    private func activate(_ conversation: Conversation, in model: AppModel) {
        model.foregroundRun.stop()
        model.selectedConversationID = conversation.id
        let response = model.beginTestForegroundResponse()
        model.foregroundRun.beginDevelopment(response)
    }

    private func clearActiveRun(_ model: AppModel) {
        model.foregroundRun.stop()
    }
}
