import XCTest
import VyronCore
@testable import Vyron

final class VyronUserInputDraftTests: XCTestCase {
    func testRequiresExplicitAnswersToEveryQuestionAndPreservesOrder() throws {
        let request = VyronUserInputRequest(questions: [
            VyronUserInputQuestion(id: "scope", question: "Which scope?"),
            VyronUserInputQuestion(id: "style", question: "Which style?")
        ])
        var draft = VyronUserInputDraft()
        XCTAssertNil(draft.response(to: request))
        draft.setValue("  Simple  ", for: "style")
        XCTAssertNil(draft.response(to: request))
        draft.setValue("Feature", for: "scope")
        let response = try XCTUnwrap(draft.response(to: request))
        XCTAssertEqual(response.requestID, request.id)
        XCTAssertEqual(response.answers.map(\.questionID), ["scope", "style"])
        XCTAssertEqual(response.answers.map(\.value), ["Feature", "Simple"])
    }

    func testCustomAnswerReplacesSelectionAndBoundsUTF8Size() throws {
        let request = VyronUserInputRequest(questions: [
            VyronUserInputQuestion(id: "choice", question: "Which approach?")
        ])
        var draft = VyronUserInputDraft()
        draft.setValue("Recommended", for: "choice")
        draft.setValue("My own approach", for: "choice")
        XCTAssertEqual(try XCTUnwrap(draft.response(to: request)).answers.count, 1)
        XCTAssertEqual(draft.value(for: "choice"), "My own approach")
        draft.setValue(String(repeating: "я", count: VyronUserInputLimits.maximumAnswerBytes / 2), for: "choice")
        XCTAssertNotNil(draft.response(to: request))
        draft.setValue(draft.value(for: "choice") + "я", for: "choice")
        XCTAssertNil(draft.response(to: request))
        draft.setValue(" \n ", for: "choice")
        XCTAssertNil(draft.response(to: request))
    }

    func testSkipFillsOnlyUnansweredQuestionsAndPreservesDraftAndRequestOrder() throws {
        let request = VyronUserInputRequest(questions: [
            VyronUserInputQuestion(id: "scope", question: "Which scope?"),
            VyronUserInputQuestion(id: "style", question: "Which style?"),
            VyronUserInputQuestion(id: "details", question: "Any details?")
        ])
        var draft = VyronUserInputDraft()
        draft.setValue("  My own style  ", for: "style")
        draft.setValue(" \n ", for: "details")
        let skippedAnswer = "Skip this question and use your best judgment."
        let response = try XCTUnwrap(draft.responseSkippingUnanswered(to: request, skippedAnswer: skippedAnswer))
        XCTAssertEqual(response.requestID, request.id)
        XCTAssertEqual(response.answers.map(\.questionID), ["scope", "style", "details"])
        XCTAssertEqual(response.answers.map(\.value), [skippedAnswer, "My own style", skippedAnswer])
        XCTAssertEqual(draft.value(for: "scope"), "")
        XCTAssertEqual(draft.value(for: "style"), "  My own style  ")
        XCTAssertEqual(draft.value(for: "details"), " \n ")
        XCTAssertNil(draft.response(to: request))
    }

    func testSkipRetainsAnswerValidationForExistingAndFallbackAnswers() throws {
        let request = VyronUserInputRequest(questions: [
            VyronUserInputQuestion(id: "choice", question: "Which approach?")
        ])
        var draft = VyronUserInputDraft()
        let skippedAnswer = "Use your best judgment."
        let maximumAnswer = String(repeating: "я", count: VyronUserInputLimits.maximumAnswerBytes / 2)
        XCTAssertNotNil(draft.responseSkippingUnanswered(to: request, skippedAnswer: maximumAnswer))
        XCTAssertNil(draft.responseSkippingUnanswered(to: request, skippedAnswer: maximumAnswer + "я"))
        XCTAssertNil(draft.responseSkippingUnanswered(to: request, skippedAnswer: " \n "))
        draft.setValue(maximumAnswer + "я", for: "choice")
        XCTAssertNil(draft.responseSkippingUnanswered(to: request, skippedAnswer: skippedAnswer))
        draft.setValue("Keep my selection", for: "choice")
        XCTAssertEqual(
            try XCTUnwrap(draft.responseSkippingUnanswered(to: request, skippedAnswer: skippedAnswer))
                .answers.first?.value,
            "Keep my selection"
        )
    }
}
