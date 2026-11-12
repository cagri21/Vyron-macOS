import Foundation
import XCTest
import VyronCore
@testable import Vyron

final class VyronTrackingPresentationTests: XCTestCase {
    func testCompletedDurationStaysFixedWhileWallClockAdvances() {
        let start = Date(timeIntervalSince1970: 1_000)
        var activity = ResponseActivity(startedAt: start)
        activity.finish(.completed, at: start.addingTimeInterval(15))
        let presentation = VyronTrackingPresentation(activity: activity, isLive: false)
        XCTAssertEqual(
            presentation.elapsedTitle(at: start.addingTimeInterval(300)),
            VyronTrackingText.workedFor(VyronAppText.activitySeconds(15))
        )
        XCTAssertEqual(presentation.phase, VyronTrackingText.completed)
    }

    func testLivePhaseKeepsToolTitleAndUsesThinkingBetweenTools() {
        var activity = ResponseActivity()
        activity.record("Preparing a response")
        XCTAssertEqual(
            VyronTrackingPresentation(activity: activity, isLive: true).phase,
            VyronTrackingText.thinking
        )
        activity.record("Reading Sources/Feature.swift", kind: .tool)
        XCTAssertEqual(
            VyronTrackingPresentation(activity: activity, isLive: true).phase,
            "Reading Sources/Feature.swift"
        )
        activity.record("The model is preparing the next step")
        XCTAssertEqual(
            VyronTrackingPresentation(activity: activity, isLive: true).phase,
            VyronTrackingText.thinking
        )
    }

    func testInlineThinkingDoesNotRepeatTheToolRowTitle() {
        var activity = ResponseActivity()
        activity.record("Reading Sources/Feature.swift", kind: .tool)
        let presentation = VyronTrackingPresentation(activity: activity, isLive: true)

        XCTAssertEqual(presentation.inlinePhase, VyronTrackingText.thinking)
        XCTAssertNotEqual(presentation.inlinePhase, presentation.phase)
    }

    func testStoppedAndFailedPhasesRetainTheirOutcome() {
        for state in [ResponseActivity.State.stopped, .failed] {
            var activity = ResponseActivity()
            activity.record("Running a local check", kind: .tool)
            activity.finish(state)
            let presentation = VyronTrackingPresentation(activity: activity, isLive: false)
            XCTAssertEqual(presentation.phase, VyronTrackingPresentation.status(state))
            XCTAssertNotEqual(presentation.phase, "Running a local check")
        }
    }

    func testPendingQuestionUsesLocalizedWaitingPhase() {
        var activity = ResponseActivity()
        activity.record(VyronActivityContent(
            kind: .tool,
            title: "A question from the model",
            category: .question
        ))
        XCTAssertEqual(
            VyronTrackingPresentation(activity: activity, isLive: true).phase,
            VyronQuestionText.waitingForAnswer
        )
        XCTAssertEqual(
            VyronTrackingPresentation(activity: activity, isLive: true).inlinePhase,
            VyronQuestionText.waitingForAnswer
        )
    }

    func testDurationHandlesInvalidAndNegativeValues() {
        XCTAssertEqual(VyronTrackingPresentation.duration(-30), VyronAppText.activitySeconds(0))
        XCTAssertEqual(VyronTrackingPresentation.duration(.infinity), VyronAppText.activitySeconds(0))
        XCTAssertEqual(VyronTrackingPresentation.duration(61), VyronAppText.activityMinutesSeconds(1, 1))
    }
}
