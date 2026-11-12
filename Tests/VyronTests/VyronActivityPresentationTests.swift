import Foundation
import VyronCore
import XCTest
@testable import Vyron

final class VyronActivityPresentationTests: XCTestCase {
    func testFreshLiveResponseShowsThinkingBeforeAnyActivityArrives() {
        let activity = ResponseActivity()
        let live = VyronActivityPresentation(activity: activity, response: "", isStreaming: true)

        XCTAssertTrue(live.isVisible)
        XCTAssertTrue(live.blocks.isEmpty)
        XCTAssertEqual(
            VyronTrackingPresentation(activity: activity, isLive: true).inlinePhase,
            VyronTrackingText.thinking
        )
        XCTAssertFalse(VyronActivityPresentation(activity: activity, response: "", isStreaming: false).isVisible)
    }

    func testCompletedResponseWithoutToolsRetainsClickableActivityAccess() {
        var activity = ResponseActivity()
        activity.finish(.completed)

        XCTAssertTrue(VyronActivityPresentation(activity: activity, response: "The answer.", isStreaming: false).isVisible)
    }

    func testToolSummaryDescribesKindsWithoutRepeatingStartAndFinishEvents() {
        var activity = ResponseActivity()
        for category in [VyronActivityCategory.read, .files, .command, .command] {
            activity.record(VyronActivityContent(kind: .tool, title: UUID().uuidString, category: category))
        }
        let group = VyronActivityToolGroup(id: UUID(), entries: activity.entries)

        XCTAssertEqual(group.summary.components(separatedBy: ", ").count, 2)
        XCTAssertTrue(group.summary.localizedCaseInsensitiveContains(VyronTrackingText.readFiles))
        XCTAssertTrue(group.summary.localizedCaseInsensitiveContains(VyronTrackingText.ranCommands))
        XCTAssertFalse(group.summary.contains(activity.entries[0].title))
    }

    func testGroupsToolsAcrossStatusesAndPreservesCommentaryOrder() {
        var activity = ResponseActivity()
        activity.record("Preparing request")
        activity.record("Reading notes", detail: "README.md", kind: .tool)
        activity.record("Considering the next step")
        activity.record("Searching files", detail: "Sources", kind: .tool)
        activity.record("AI explanation", detail: "I found the relevant screen.", kind: .explanation)
        activity.record("Editing screen", detail: "Screen.swift", kind: .tool)

        let presentation = VyronActivityPresentation(activity: activity, response: "", isStreaming: true)

        XCTAssertEqual(presentation.blocks, [
            .tools(VyronActivityToolGroup(id: activity.entries[1].id, entries: [
                activity.entries[1], activity.entries[3]
            ])),
            .explanation(VyronActivityExplanation(
                id: activity.entries[4].id,
                text: "I found the relevant screen."
            )),
            .tools(VyronActivityToolGroup(id: activity.entries[5].id, entries: [activity.entries[5]]))
        ])
        XCTAssertNil(presentation.currentStatus)
    }

    func testRemovesOnlyLastExplanationMatchingFinalAnswerWithAppendedSections() {
        var activity = ResponseActivity()
        activity.record("AI explanation", detail: "The screen is ready.", kind: .explanation)
        activity.record("Reading notes", kind: .tool)
        activity.record("AI explanation", detail: "  The screen is ready.\n", kind: .explanation)
        activity.record("Response ready")
        activity.finish(.completed)

        let presentation = VyronActivityPresentation(
            activity: activity,
            response: "\nThe screen is ready.\n\n**Changed files**\n- Screen.swift",
            isStreaming: false
        )

        XCTAssertEqual(presentation.blocks.map(\.id), [activity.entries[0].id, activity.entries[1].id])
        XCTAssertEqual(presentation.blocks.first, .explanation(VyronActivityExplanation(
            id: activity.entries[0].id,
            text: "The screen is ready."
        )))
        XCTAssertNil(presentation.currentStatus)
    }

    func testRecognizesFinalExplanationTruncatedByActivityRetentionLimit() {
        var activity = ResponseActivity()
        let summary = String(repeating: "a", count: 6_200)
        activity.record("AI explanation", detail: summary, kind: .explanation)
        activity.record("Response ready")
        activity.finish(.completed)
        XCTAssertEqual(activity.entries.first?.detail?.count, 6_000)

        let presentation = VyronActivityPresentation(activity: activity, response: summary, isStreaming: false)

        XCTAssertTrue(presentation.blocks.isEmpty)
    }

    func testKeepsGenuineProgressWhenCompletedAnswerDiffersOrIsEmpty() {
        var activity = ResponseActivity()
        activity.record("AI explanation", detail: "I will inspect the screen.", kind: .explanation)
        activity.record("Response ready")
        activity.finish(.completed)

        for response in ["", "The screen now uses an inline activity stream."] {
            let presentation = VyronActivityPresentation(activity: activity, response: response, isStreaming: false)

            XCTAssertEqual(presentation.blocks, [.explanation(VyronActivityExplanation(
                id: activity.entries[0].id,
                text: "I will inspect the screen."
            ))])
        }
    }

    func testKeepsMatchingExplanationWhileWorkingStoppedOrFailed() {
        for state in [ResponseActivity.State.working, .stopped, .failed] {
            var activity = ResponseActivity()
            activity.record("AI explanation", detail: "Work completed so far.", kind: .explanation)
            if state != .working {
                activity.record("Run ended", detail: "Remaining work is available for review.")
                activity.finish(state)
            }

            let presentation = VyronActivityPresentation(
                activity: activity,
                response: "Work completed so far.",
                isStreaming: state == .working
            )

            XCTAssertEqual(presentation.blocks.map(\.id), [activity.entries[0].id])
        }
    }

    func testCoalescesToolGroupsAcrossRemovedFinalExplanation() {
        var activity = ResponseActivity()
        activity.record("Reading notes", kind: .tool)
        activity.record("AI explanation", detail: "The answer.", kind: .explanation)
        activity.record("Command exited 0", kind: .tool)
        activity.record("Response ready")
        activity.finish(.completed)

        let presentation = VyronActivityPresentation(
            activity: activity,
            response: "The answer.",
            isStreaming: false
        )

        XCTAssertEqual(presentation.blocks, [.tools(VyronActivityToolGroup(
            id: activity.entries[0].id,
            entries: [activity.entries[0], activity.entries[2]]
        ))])
    }

    func testCurrentStatusRequiresLatestStatusAndLiveStreamingWork() {
        var activity = ResponseActivity()
        activity.record("Preparing context")

        XCTAssertEqual(
            VyronActivityPresentation(activity: activity, response: "", isStreaming: true).currentStatus,
            activity.entries.last
        )
        XCTAssertNil(VyronActivityPresentation(activity: activity, response: "", isStreaming: false).currentStatus)

        activity.record("Reading notes", kind: .tool)
        XCTAssertNil(VyronActivityPresentation(activity: activity, response: "", isStreaming: true).currentStatus)
        activity.record("AI explanation", detail: "I found the entry point.", kind: .explanation)
        XCTAssertNil(VyronActivityPresentation(activity: activity, response: "", isStreaming: true).currentStatus)
    }

    func testShowsTerminalStoppedAndFailedStatusesButHidesCompletedStatus() {
        for state in [ResponseActivity.State.completed, .stopped, .failed] {
            var activity = ResponseActivity()
            activity.record("Run ended", detail: "Terminal detail")
            activity.finish(state)

            for isStreaming in [false, true] {
                let presentation = VyronActivityPresentation(
                    activity: activity,
                    response: "",
                    isStreaming: isStreaming
                )

                XCTAssertEqual(presentation.currentStatus, state == .completed ? nil : activity.entries.last)
            }
        }
    }

    func testStableBlockIDsSurviveToolUpdatesAndReconstruction() {
        var activity = ResponseActivity()
        activity.record("AI explanation", detail: "I will inspect the files.", kind: .explanation)
        activity.record("Reading notes", kind: .tool)
        let initial = VyronActivityPresentation(activity: activity, response: "", isStreaming: true)
        activity.record("Considering the next step")
        activity.record("Searching files", kind: .tool)

        let updated = VyronActivityPresentation(activity: activity, response: "", isStreaming: true)
        let reconstructed = VyronActivityPresentation(activity: activity, response: "", isStreaming: true)

        XCTAssertEqual(initial.blocks.map(\.id), updated.blocks.map(\.id))
        XCTAssertEqual(updated, reconstructed)
    }

    func testExplanationWithoutDetailUsesTitleAndIsNotRemovedAsDuplicate() {
        var activity = ResponseActivity()
        activity.record("Public progress", kind: .explanation)
        activity.finish(.completed)

        let presentation = VyronActivityPresentation(
            activity: activity,
            response: "Public progress",
            isStreaming: false
        )

        XCTAssertEqual(presentation.blocks, [.explanation(VyronActivityExplanation(
            id: activity.entries[0].id,
            text: "Public progress"
        ))])
    }
}
