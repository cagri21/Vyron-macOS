import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronTaskTimingTests: XCTestCase {
    func testEachTurnKeepsItsOwnResponseStartDate() {
        let firstStart = Date(timeIntervalSince1970: 1_000)
        let secondStart = firstStart.addingTimeInterval(600)
        let firstUser = ChatMessage(role: "user", content: "First task")
        let secondUser = ChatMessage(role: "user", content: "Second task")
        let messages = [
            firstUser, answer(startedAt: firstStart), secondUser, answer(startedAt: secondStart)
        ]

        let timeline = VyronConversationTimeline(messages: messages)

        XCTAssertEqual(timeline.startDatesByMessageID, [firstUser.id: firstStart, secondUser.id: secondStart])
    }

    func testConsecutiveQueuedOrSteeredUserMessagesShareOneTurnStart() {
        let start = Date(timeIntervalSince1970: 1_000)
        let original = ChatMessage(role: "user", content: "Original task")
        let steering = ChatMessage(role: "user", content: "A correction during work")
        let clarification = ChatMessage(role: "user", content: "Another detail")
        let later = ChatMessage(role: "user", content: "A later queued follow-up")

        let timeline = VyronConversationTimeline(messages: [
            original, steering, clarification, answer(startedAt: start),
            later, answer(startedAt: start.addingTimeInterval(60))
        ])

        XCTAssertEqual(timeline.startDatesByMessageID, [original.id: start, later.id: start.addingTimeInterval(60)])
        XCTAssertNil(timeline.startDatesByMessageID[steering.id])
        XCTAssertNil(timeline.startDatesByMessageID[clarification.id])
    }

    func testLegacyAndUnansweredMessagesDoNotReceiveFabricatedDates() {
        let legacy = ChatMessage(role: "user", content: "A legacy request")
        let pending = ChatMessage(role: "user", content: "Not sent to the model yet")
        let timeline = VyronConversationTimeline(messages: [
            legacy, ChatMessage(role: "assistant", content: "A legacy answer without activity"), pending
        ])

        XCTAssertTrue(timeline.startDatesByMessageID.isEmpty)
    }

    func testLegacyTurnDoesNotBorrowDateFromTheFollowingResponse() {
        let start = Date(timeIntervalSince1970: 1_000)
        let legacy = ChatMessage(role: "user", content: "Legacy request")
        let current = ChatMessage(role: "user", content: "Current request")
        let timeline = VyronConversationTimeline(messages: [
            legacy, ChatMessage(role: "assistant", content: "Legacy answer"), current, answer(startedAt: start)
        ])

        XCTAssertEqual(timeline.startDatesByMessageID, [current.id: start])
    }

    func testCompletedStoppedAndFailedElapsedTimesFreezeAtTheirOwnFinish() {
        let start = Date(timeIntervalSince1970: 1_000)
        for state in [ResponseActivity.State.completed, .stopped, .failed] {
            var activity = ResponseActivity(startedAt: start)
            activity.record("A final recorded step", at: start.addingTimeInterval(20))
            activity.finish(state, at: start.addingTimeInterval(61))
            for liveFlag in [false, true] {
                let presentation = VyronTrackingPresentation(activity: activity, isLive: liveFlag)
                let expected = VyronTrackingText.workedFor(VyronAppText.activityMinutesSeconds(1, 1))
                XCTAssertEqual(presentation.elapsedTitle(at: start.addingTimeInterval(200)), expected)
                XCTAssertEqual(presentation.elapsedTitle(at: start.addingTimeInterval(2_000)), expected)
            }
        }
    }

    func testInactiveWorkingActivityFreezesAtItsLatestRecordedTime() {
        let start = Date(timeIntervalSince1970: 1_000)
        var activity = ResponseActivity(startedAt: start)
        activity.record("Last known progress", at: start.addingTimeInterval(18))
        let presentation = VyronTrackingPresentation(activity: activity, isLive: false)
        let expected = VyronTrackingText.workedFor(VyronAppText.activitySeconds(18))

        XCTAssertEqual(presentation.elapsedTitle(at: start.addingTimeInterval(100)), expected)
        XCTAssertEqual(presentation.elapsedTitle(at: start.addingTimeInterval(10_000)), expected)
    }

    func testInactiveWorkingActivityWithoutEventsStaysAtZero() {
        let start = Date(timeIntervalSince1970: 1_000)
        let presentation = VyronTrackingPresentation(activity: ResponseActivity(startedAt: start), isLive: false)

        XCTAssertEqual(
            presentation.elapsedTitle(at: start.addingTimeInterval(10_000)),
            VyronTrackingText.workedFor(VyronAppText.activitySeconds(0))
        )
    }

    func testOnlyLiveWorkingResponseContinuesCountingElapsedTime() {
        let start = Date(timeIntervalSince1970: 1_000)
        var activity = ResponseActivity(startedAt: start)
        activity.record("Progress", at: start.addingTimeInterval(5))
        let presentation = VyronTrackingPresentation(activity: activity, isLive: true)

        XCTAssertEqual(
            presentation.elapsedTitle(at: start.addingTimeInterval(20)),
            VyronTrackingText.workingFor(VyronAppText.activitySeconds(20))
        )
        XCTAssertEqual(
            presentation.elapsedTitle(at: start.addingTimeInterval(40)),
            VyronTrackingText.workingFor(VyronAppText.activitySeconds(40))
        )
    }

    func testWholeMinutesOmitZeroSecondsWhileMixedDurationsRetainThem() {
        XCTAssertEqual(
            VyronTrackingPresentation.duration(240),
            VyronTrackingText.durationMinutes(4)
        )
        XCTAssertEqual(
            VyronTrackingPresentation.duration(60),
            VyronTrackingText.durationMinutes(1)
        )
        XCTAssertEqual(VyronTrackingPresentation.duration(61), VyronAppText.activityMinutesSeconds(1, 1))
    }

    func testParallelHelpersUseWallClockElapsedTimeWithoutSummingTheirDurations() {
        let start = Date(timeIntervalSince1970: 1_000)
        var parent = ResponseActivity(startedAt: start)
        for index in 0..<2 {
            let identity = VyronSubagentIdentity(name: "Helper \(index)", prompt: "Read a file", model: "fixture")
            parent.recordSubagent(VyronSubagentEvent(
                identity: identity, update: .started, date: start.addingTimeInterval(Double(index + 1))
            ))
            parent.recordSubagent(VyronSubagentEvent(
                identity: identity,
                update: .finished(VyronSubagentCompletion(state: .completed, summary: "Finished reading")),
                date: start.addingTimeInterval(Double(index + 21))
            ))
        }
        let stale = VyronTrackingPresentation(activity: parent, isLive: false)
        XCTAssertEqual(
            stale.elapsedTitle(at: start.addingTimeInterval(1_000)),
            VyronTrackingText.workedFor(VyronAppText.activitySeconds(22))
        )
        parent.finish(.completed, at: start.addingTimeInterval(30))
        let completed = VyronTrackingPresentation(activity: parent, isLive: false)
        XCTAssertEqual(
            completed.elapsedTitle(at: start.addingTimeInterval(1_000)),
            VyronTrackingText.workedFor(VyronAppText.activitySeconds(30))
        )
    }

    private func answer(startedAt: Date) -> ChatMessage {
        ChatMessage(role: "assistant", content: "A response", activity: ResponseActivity(startedAt: startedAt))
    }
}
