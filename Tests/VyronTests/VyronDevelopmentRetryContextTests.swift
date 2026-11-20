import Foundation
import XCTest
import VyronCore
@testable import Vyron

final class VyronDevelopmentRetryContextTests: XCTestCase {
    func testRepeatedInspectionOmitsStaleRootAnswersAndPreservesUserGuidanceAttachmentsAndStoredHistory() throws {
        let image = VyronImageAttachment(name: "reference.png", mimeType: "image/png", data: Data([1, 2, 3]))
        let rules = ChatMessage(role: "system", content: "Keep the selected project and skills.")
        let constraint = ChatMessage(role: "user", content: "Remain local and preserve saved data.")
        let prior = ChatMessage(role: "user", content: "analyze the code", images: [image])
        let bad = ChatMessage(role: "assistant", content: "BAD_ARCHITECTURE_CANARY comprehensive model implementation")
        let repeated = ChatMessage(role: "user", content: "analyze the code")
        let copiedBad = ChatMessage(role: "assistant", content: "BAD_ARCHITECTURE_CANARY copied answer")
        var latest = ChatMessage(role: "user", content: "  analyze the code\n", images: [image])
        latest.developmentTaskFilename = "task.txt"
        latest.pdfPreviews = [VyronPDFPreview(name: "Reference.pdf", imageData: Data([4]))]
        latest.fileAttachments = [VyronFileAttachmentInfo(name: "source.py", kind: .document)]
        latest.applicationAttachments = [VyronApplicationAttachment(name: "Fixture", path: "/Applications/Fixture.app")]
        let history = [rules, constraint, prior, bad, repeated, copiedBad, latest]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let saved = try encoder.encode(history)

        let context = VyronDevelopmentRetryContext(prompt: latest.content, history: history, compaction: nil)

        XCTAssertTrue(context.isFreshRetry)
        XCTAssertEqual(context.messages, [rules, constraint, prior, repeated, latest])
        XCTAssertEqual(context.referenceMessages, [rules, constraint, prior, latest])
        XCTAssertEqual(context.messages.filter { $0.conversationRole == .user },
                       history.filter { $0.conversationRole == .user })
        XCTAssertEqual(context.messages.last?.images, [image])
        XCTAssertEqual(context.messages.last?.fileAttachments, latest.fileAttachments)
        XCTAssertEqual(context.messages.last?.pdfPreviews, latest.pdfPreviews)
        XCTAssertEqual(context.messages.last?.applicationAttachments, latest.applicationAttachments)
        XCTAssertFalse(context.messages.contains { $0.content.contains("BAD_ARCHITECTURE_CANARY") })
        XCTAssertEqual(try encoder.encode(history), saved)
    }

    func testEarlierPlanBeforeTheRepeatedGoalBlockRemainsAvailableForDependentWork() {
        let planRequest = ChatMessage(role: "user", content: "Plan the migration.")
        let plan = ChatMessage(role: "assistant", content: "REQUIRED_PLAN: preserve legacy profile identity.")
        let first = ChatMessage(role: "user", content: "Implement that plan.")
        let attempt = ChatMessage(role: "assistant", content: "STALE_ATTEMPT: previous implementation claim.")
        let second = ChatMessage(role: "user", content: "Implement that plan.")
        let history = [planRequest, plan, first, attempt, second]

        let context = VyronDevelopmentRetryContext(prompt: second.content, history: history, compaction: nil)

        XCTAssertTrue(context.isFreshRetry)
        XCTAssertEqual(context.messages, [planRequest, plan, first, second])
        let reference = VyronConversationRequestContext.developmentConversationContext(
            Array(context.referenceMessages.dropLast())
        )
        XCTAssertTrue(reference?.contains("REQUIRED_PLAN") == true)
        XCTAssertFalse(reference?.contains("STALE_ATTEMPT") == true)
    }

    func testOwnedClarificationChildrenAndTheirUserAnswersRemainWhenTheirRootAnswerIsOmitted() {
        let first = ChatMessage(role: "user", content: "Analyze the code.")
        let root = ChatMessage(role: "assistant", content: "STALE_ROOT_ANSWER")
        var question = ChatMessage(role: "assistant", content: "Which scope should I inspect?")
        question.parentResponseID = root.id
        var reply = ChatMessage(role: "user", content: "The CLI and web demos; remain read-only.")
        reply.parentResponseID = root.id
        let latest = ChatMessage(role: "user", content: "Analyze the code.")
        let history = [first, question, reply, root, latest]

        let context = VyronDevelopmentRetryContext(prompt: latest.content, history: history, compaction: nil)

        XCTAssertTrue(context.isFreshRetry)
        XCTAssertEqual(context.messages, [first, question, reply, latest])
        XCTAssertEqual(context.referenceMessages, [question, reply, latest])
        XCTAssertEqual(context.messages.first { $0.id == reply.id }?.parentResponseID, root.id)
    }

    func testFreshRetryBypassesCompactionWithoutChangingItsSavedBoundaryOrReintroducingAssistantClaims() {
        let first = ChatMessage(role: "user", content: "analyze the code")
        let bad = ChatMessage(role: "assistant", content: "BAD_COMPACTED_CANARY")
        let compact = ChatMessage(role: "user", content: "/compact retain the current task")
        let confirmation = ChatMessage(role: "assistant", content: "The context was compacted.")
        let latest = ChatMessage(role: "user", content: "analyze the code")
        let history = [first, bad, compact, confirmation, latest]
        let snapshot = VyronConversationCompaction(
            summary: "BAD_COMPACTED_CANARY is a comprehensive implementation.", throughMessageID: confirmation.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let context = VyronDevelopmentRetryContext(prompt: latest.content, history: history, compaction: snapshot)
        let inference = VyronConversationRequestContext.boundedHistory(
            context.messages, context: [:], compaction: context.compaction
        )

        XCTAssertTrue(context.isFreshRetry)
        XCTAssertNil(context.compaction)
        XCTAssertEqual(context.messages, [first, compact, latest])
        XCTAssertFalse(inference.messages.contains { $0.content.contains("BAD_COMPACTED_CANARY") })
        XCTAssertEqual(snapshot.throughMessageID, confirmation.id)
        XCTAssertEqual(snapshot.summary, "BAD_COMPACTED_CANARY is a comprehensive implementation.")
        XCTAssertEqual(history, [first, bad, compact, confirmation, latest])
    }

    func testFirstDifferentAndNonexactGoalsKeepTheOriginalHistoryAndCompaction() {
        let original = ChatMessage(role: "user", content: "analyze the code")
        let answer = ChatMessage(role: "assistant", content: "A plan needed by future requests.")
        let snapshot = VyronConversationCompaction(summary: "Keep the existing plan.", throughMessageID: answer.id)
        for prompt in ["analyze the code", "implement that plan", "Analyze the code", "analyze  the code"] {
            let latest = ChatMessage(role: "user", content: prompt)
            let history = prompt == "analyze the code" ? [latest] : [original, answer, latest]

            let context = VyronDevelopmentRetryContext(prompt: prompt, history: history, compaction: snapshot)

            XCTAssertFalse(context.isFreshRetry)
            XCTAssertEqual(context.messages, history)
            XCTAssertEqual(context.referenceMessages, history)
            XCTAssertEqual(context.compaction, snapshot)
        }
    }

    func testRepeatedContinuationsAndLocalizedConfirmationsKeepTheirAssistantDependencies() {
        for prompt in [
            "continue", "please continue", "devam et", "продовжуй", "yes", "NO", "okay!", "go ahead", "do it",
            "yes please", "evet", "hayır", "Tamam!", "так", "ні", "гаразд"
        ] {
            let prior = ChatMessage(role: "user", content: prompt)
            let answer = ChatMessage(role: "assistant", content: "Required prior answer or action result.")
            let latest = ChatMessage(role: "user", content: prompt)
            let history = [prior, answer, latest]
            let snapshot = VyronConversationCompaction(summary: "Retain the prior answer.", throughMessageID: answer.id)

            let context = VyronDevelopmentRetryContext(prompt: prompt, history: history, compaction: snapshot)

            XCTAssertFalse(context.isFreshRetry, prompt)
            XCTAssertEqual(context.messages, history, prompt)
            XCTAssertEqual(context.compaction, snapshot, prompt)
        }
    }

    func testRepeatedGoalDoesNotCrossAnInterveningDifferentRootRequest() {
        let old = ChatMessage(role: "user", content: "analyze the code")
        let answer = ChatMessage(role: "assistant", content: "Old answer")
        let different = ChatMessage(role: "user", content: "Explain that finding.")
        let explanation = ChatMessage(role: "assistant", content: "The required explanation.")
        let latest = ChatMessage(role: "user", content: "analyze the code")
        let history = [old, answer, different, explanation, latest]

        let context = VyronDevelopmentRetryContext(prompt: latest.content, history: history, compaction: nil)

        XCTAssertFalse(context.isFreshRetry)
        XCTAssertEqual(context.messages, history)
    }

    func testMismatchedCapturedCurrentGoalDoesNotProjectAnotherSubmission() {
        let prior = ChatMessage(role: "user", content: "analyze the code")
        let answer = ChatMessage(role: "assistant", content: "Keep this answer for the captured submission.")
        let latest = ChatMessage(role: "user", content: "analyze the code")
        let history = [prior, answer, latest]

        let context = VyronDevelopmentRetryContext(prompt: "A different live draft.", history: history, compaction: nil)

        XCTAssertFalse(context.isFreshRetry)
        XCTAssertEqual(context.messages, history)
    }

    func testRepeatedUnansweredOrEmptyRootTurnsDoNotDiscardExistingMemory() {
        let first = ChatMessage(role: "user", content: "analyze the code")
        let latest = ChatMessage(role: "user", content: "analyze the code")
        let snapshot = VyronConversationCompaction(summary: "Keep genuine earlier constraints.", throughMessageID: first.id)
        let emptyRoot = ChatMessage(role: "assistant", content: "")
        var question = ChatMessage(role: "assistant", content: "A clarification question is not a final root answer.")
        question.parentResponseID = emptyRoot.id
        for history in [
            [first, latest],
            [first, ChatMessage(role: "assistant", content: ""), latest],
            [first, ChatMessage(role: "assistant", content: " \n\t "), latest],
            [first, question, emptyRoot, latest],
            [first, ChatMessage(role: "user", content: "/compact"),
             ChatMessage(role: "assistant", content: "Context compacted."), latest]
        ] {
            let context = VyronDevelopmentRetryContext(prompt: latest.content, history: history, compaction: snapshot)

            XCTAssertFalse(context.isFreshRetry)
            XCTAssertEqual(context.messages, history)
            XCTAssertEqual(context.compaction, snapshot)
        }
    }

    func testRepeatedTextReferencesKeepOlderConstraintsWithinTheBoundedContext() {
        let constraint = ChatMessage(role: "user", content: "REAL_CONSTRAINT: remain local and preserve data.")
        let goal = "analyze the code"
        var history = [constraint]
        for index in 0..<8 {
            history.append(ChatMessage(role: "user", content: goal))
            history.append(ChatMessage(role: "assistant", content: "STALE_ANSWER_\(index)"))
        }
        let current = ChatMessage(role: "user", content: goal)
        history.append(current)

        let context = VyronDevelopmentRetryContext(prompt: goal, history: history, compaction: nil)
        let reference = VyronConversationRequestContext.developmentConversationContext(
            Array(context.referenceMessages.dropLast())
        )

        XCTAssertTrue(context.isFreshRetry)
        XCTAssertEqual(context.messages.filter { $0.conversationRole == .user },
                       history.filter { $0.conversationRole == .user })
        XCTAssertEqual(context.referenceMessages, [constraint, current])
        XCTAssertTrue(reference?.contains("REAL_CONSTRAINT") == true)
        XCTAssertFalse(reference?.contains("STALE_ANSWER") == true)
        XCTAssertEqual(history.count, 18)
    }

    func testTextProjectionPreservesEveryAttachmentBearingDuplicateGoal() {
        let goal = "analyze the code"
        let constraint = ChatMessage(role: "user", content: "Keep all selected references.")
        let image = VyronImageAttachment(name: "Reference.png", mimeType: "image/png", data: Data([1]))
        let withImage = ChatMessage(role: "user", content: goal, images: [image])
        var withPDF = ChatMessage(role: "user", content: goal)
        withPDF.pdfPreviews = [VyronPDFPreview(name: "Reference.pdf", imageData: Data([2]))]
        var withFile = ChatMessage(role: "user", content: goal)
        withFile.fileAttachments = [VyronFileAttachmentInfo(name: "source.py", kind: .document)]
        var withApplication = ChatMessage(role: "user", content: goal)
        withApplication.applicationAttachments = [VyronApplicationAttachment(name: "Fixture", path: "/Applications/Fixture.app")]
        var withTask = ChatMessage(role: "user", content: goal)
        withTask.developmentTaskFilename = "task.txt"
        let references = [withImage, withPDF, withFile, withApplication, withTask]
        var history = [constraint]
        for message in references + [ChatMessage(role: "user", content: goal)] {
            history.append(message)
            history.append(ChatMessage(role: "assistant", content: "A stale answer."))
        }
        let current = ChatMessage(role: "user", content: goal)
        history.append(current)

        let context = VyronDevelopmentRetryContext(prompt: goal, history: history, compaction: nil)

        XCTAssertTrue(context.isFreshRetry)
        XCTAssertEqual(context.referenceMessages, [constraint] + references + [current])
        XCTAssertEqual(context.messages.filter { $0.conversationRole == .user },
                       history.filter { $0.conversationRole == .user })
    }
}
