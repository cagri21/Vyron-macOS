import Foundation
import XCTest
@testable import VyronCore

final class VyronDevelopmentContinuationGuidanceOverlapTests: XCTestCase {
    func testSavedRepresentationPrefixDoesNotRepeatTheTranscriptTail() throws {
        var task = task()
        let original = ["Saved JSON clarification.", "Use blue.", "Use red.", "Use blue."]
        for instruction in original { try task.recordGuidance(instruction) }

        try task.mergeContinuationGuidance(["Use blue.", "Use red.", "Use blue."])
        try task.mergeContinuationGuidance(["Use blue.", "Use red.", "Use blue."])

        XCTAssertEqual(task.guidance, original)
    }

    func testPartialTailOverlapPreservesANewReturnToAnEarlierConstraint() throws {
        var task = task()
        for instruction in ["Saved JSON clarification.", "Use blue.", "Use red."] {
            try task.recordGuidance(instruction)
        }

        try task.mergeContinuationGuidance(["Use red.", "Use blue."])
        try task.mergeContinuationGuidance(["Use red.", "Use blue."])

        XCTAssertEqual(task.guidance, ["Saved JSON clarification.", "Use blue.", "Use red.", "Use blue."])
    }

    func testSharedHistoricalPrefixStillAppendsAnOrderedRevision() throws {
        var task = task()
        try task.recordGuidance("Use blue.")
        try task.recordGuidance("Use red.")

        try task.mergeContinuationGuidance(["Use blue.", "Use red.", "Use blue."])

        XCTAssertEqual(task.guidance, ["Use blue.", "Use red.", "Use blue."])
    }

    private func task() -> VyronDevelopmentTaskState {
        VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: UUID(), projectPath: "/FixtureProject", originalGoal: "Build the original app."
        ))
    }
}
