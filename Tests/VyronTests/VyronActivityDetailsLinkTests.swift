import XCTest
import VyronCore
@testable import Vyron

final class VyronActivityDetailsLinkTests: XCTestCase {
    func testFinishedToolWorkOffersActivityDetailsForEveryTerminalState() {
        for state in [ResponseActivity.State.completed, .stopped, .failed] {
            var activity = ResponseActivity()
            activity.record("Updated file", detail: "Screen.swift", kind: .tool)
            activity.finish(state)

            let presentation = VyronActivityPresentation(
                activity: activity,
                response: "Updated the screen.",
                isStreaming: false
            )

            XCTAssertTrue(presentation.showsDetailsLink)
            XCTAssertEqual(activity.entries.first?.detail, "Screen.swift")
        }
    }

    func testSimpleReplyDoesNotAddAnEmptyDetailsLink() {
        var activity = ResponseActivity()
        activity.record("Response ready")
        activity.finish(.completed)

        let presentation = VyronActivityPresentation(activity: activity, response: "Hello.", isStreaming: false)

        XCTAssertFalse(presentation.showsDetailsLink)
    }

    func testLiveWorkKeepsItsExistingTrackingActionWithoutAnExtraLink() {
        var activity = ResponseActivity()
        activity.record("Running check", detail: "swift test", kind: .tool)

        for isStreaming in [true, false] {
            let presentation = VyronActivityPresentation(activity: activity, response: "", isStreaming: isStreaming)

            XCTAssertFalse(presentation.showsDetailsLink)
        }
        activity.finish(.completed)
        XCTAssertFalse(VyronActivityPresentation(activity: activity, response: "", isStreaming: true).showsDetailsLink)
    }
}
