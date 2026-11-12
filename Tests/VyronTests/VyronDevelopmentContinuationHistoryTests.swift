import Foundation
import XCTest
import VyronCore
@testable import Vyron

final class VyronDevelopmentContinuationHistoryTests: XCTestCase {
    func testOriginalIOSGoalSurvivesThreeContinueTurnsIncludingTheLegacyTypo() throws {
        let goal = "Create a minimal iOS template app with a welcome screen and settings."
        let answers = (0..<4).map { answer("Recorded response \($0)") }
        var messages = [user(goal), answers[0]]

        for (index, continuation) in ["Continue", "continıe", "Continue"].enumerated() {
            messages.append(user(continuation))
            let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(
                for: continuation, messages: messages
            ))

            XCTAssertEqual(context.originalGoal, goal)
            XCTAssertEqual(context.priorResponseIDs, Array(answers.prefix(index + 1)).map(\.id))
            XCTAssertTrue(context.guidance.isEmpty)
            messages.append(answers[index + 1])
        }
    }

    func testNormalNewGoalDoesNotAttachContinuationEvidence() {
        let messages = [user("Create an iOS app."), answer("An unfinished task."), user("Add logging instead.")]

        XCTAssertNil(VyronDevelopmentContinuationHistory.context(for: "Add logging instead.", messages: messages))
        XCTAssertNil(VyronDevelopmentContinuationHistory.context(
            for: "Continue with a different project and create a new app.", messages: messages
        ))
    }

    func testFirstUserInAConsecutiveGuidanceGroupOwnsTheGoal() throws {
        let goal = "Create the iOS template app."
        let response = answer("Use a red accent instead; this assistant text is not user guidance.")
        let messages = [
            user(goal),
            user("Keep its screens minimal."),
            user(" \n "),
            user("Use a blue accent, as requested in the clarification."),
            response,
            user("Continue")
        ]

        let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: messages))

        XCTAssertEqual(context.originalGoal, goal)
        XCTAssertEqual(context.priorResponseIDs, [response.id])
        XCTAssertEqual(context.guidance, [
            "Keep its screens minimal.",
            "Use a blue accent, as requested in the clarification."
        ])
    }

    func testGuidanceAfterAContinueDoesNotResetTheOriginalAnchor() throws {
        let goal = "Create the original iOS template app."
        let first = answer("Initial work remains incomplete.")
        let second = answer("The continued task remains incomplete.")
        let messages = [
            user(goal), user("Keep the app offline."), first,
            user("Continue"), user("Continue"), user("Preserve the saved data format."), second,
            user("Continue")
        ]

        let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: messages))

        XCTAssertEqual(context.originalGoal, goal)
        XCTAssertEqual(context.priorResponseIDs, [first.id, second.id])
        XCTAssertEqual(context.guidance, ["Keep the app offline.", "Preserve the saved data format."])
    }

    func testLatestSubstantiveTaskExcludesEarlierUnrelatedResponseIDs() throws {
        let unrelated = answer("The earlier task is complete.")
        let relevant = answer("The new iOS task is incomplete.")
        let goal = "Create a new iOS template app."
        let messages = [
            user("Explain a database query."), user("Use the old database schema."), unrelated,
            user(goal), user("Keep its UI simple."), relevant,
            user("Continue")
        ]

        let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: messages))

        XCTAssertEqual(context.originalGoal, goal)
        XCTAssertEqual(context.priorResponseIDs, [relevant.id])
        XCTAssertFalse(context.priorResponseIDs.contains(unrelated.id))
        XCTAssertEqual(context.guidance, ["Keep its UI simple."])
    }

    func testAssistantTextCannotInventAnOriginalUserGoal() {
        let messages = [
            answer("The user originally requested an iOS app; continue that task."),
            user("Continue"), answer("Another claim about a previous goal."), user("Continue")
        ]

        XCTAssertNil(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: messages))
    }

    func testEmptyLegacyAndIncompleteHistoriesDoNotFabricateAChain() {
        let histories: [[ChatMessage]] = [
            [],
            [answer("A legacy answer with no user request.")],
            [user("Continue")],
            [user(""), answer("A legacy answer."), user("Continue")],
            [user("Create an app."), answer("A completed response without the current user request.")],
            [user("Create an app."), user("Continue")]
        ]

        for messages in histories {
            XCTAssertNil(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: messages))
        }
    }

    func testCurrentGuidanceGroupCannotReachBackAcrossANewUnansweredGoal() {
        let messages = [
            user("Create an earlier app."), answer("Earlier task progress."),
            user("Create a different app."), user("Continue")
        ]

        XCTAssertNil(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: messages))
    }

    private func user(_ content: String) -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }

    private func answer(_ content: String) -> ChatMessage {
        // Legacy responses have no activity, but their actual message identities still anchor saved checkpoints.
        ChatMessage(role: "assistant", content: content)
    }
}
