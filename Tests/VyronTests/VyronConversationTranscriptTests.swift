import XCTest
import VyronModelDomain
@testable import Vyron

final class VyronConversationTranscriptTests: XCTestCase {
    func testStructuredClarificationsShareOneRowInTheOriginalOrder() {
        let request = ChatMessage(role: .user, content: "Create a template.")
        let response = ChatMessage(role: .assistant, content: "Created the template.")
        let answers = [
            VyronClarificationAnswer(question: "Which accent?\nConsider the brand.", answer: "Blue\n\nOr teal."),
            VyronClarificationAnswer(question: "Which template?", answer: "Starter")
        ]
        let prompt = child(
            .assistant, content: "Which accent?\nConsider the brand.\n\nWhich template?", of: response.id
        )
        var reply = child(
            .user,
            content: "Which accent?\nConsider the brand.\nBlue\n\nOr teal.\n\nWhich template?\nStarter",
            of: response.id
        )
        reply.clarificationAnswers = answers

        let rows = VyronConversationTranscript(messages: [request, prompt, reply, response]).rows

        XCTAssertEqual(rows.map(\.message), [request, reply, response])
        XCTAssertEqual(rows.map(\.clarificationAnswers), [[], answers, []])
    }

    func testLegacySinglePromptCanBeRecoveredWithOrWithoutAnOptionList() {
        let response = ChatMessage(role: .assistant, content: "Using the blue palette.")
        let question = "Which accent?\nConsider the brand."
        let answer = "Blue.\n\nPlease add teal as a fallback."
        let reply = child(.user, content: question + "\n" + answer, of: response.id)

        for content in [question, question + "\n- Blue: The main palette.\n- Teal: The alternate palette."] {
            let prompt = child(.assistant, content: content, of: response.id)
            let rows = VyronConversationTranscript(messages: [prompt, reply, response]).rows

            XCTAssertEqual(rows.map(\.message), [reply, response])
            XCTAssertEqual(
                rows.first?.clarificationAnswers,
                [VyronClarificationAnswer(question: question, answer: answer)]
            )
        }
    }

    func testLegacyMultipleQuestionsAreNotMistakenForOneQuestion() {
        assertLegacyRowsStaySeparate(
            prompt: "Which accent?\n\nWhich template?",
            reply: "Which accent?\n\nWhich template?\nBlue\n\nWhich template?\nStarter"
        )
    }

    func testLegacyBulletsWithAmbiguousBoundariesKeepBothOriginalRows() {
        assertLegacyRowsStaySeparate(
            prompt: "Which style?\n- Blue\n- Teal",
            reply: "Which style?\n- Blue\n- Teal\nBoth"
        )
    }

    func testOrphanReferencesAndOrdinaryMultilineMessagesRemainSeparate() {
        let response = ChatMessage(role: .assistant, content: "Here is the template.")
        let missingOwner = UUID()
        let prompt = child(.assistant, content: "Which accent?", of: missingOwner)
        let orphanReply = child(.user, content: "Which accent?\nBlue", of: missingOwner)
        let ordinaryReply = ChatMessage(role: .user, content: "Which accent?\nBlue")
        let messages = [prompt, orphanReply, response, ordinaryReply]

        let rows = VyronConversationTranscript(messages: messages).rows

        XCTAssertEqual(rows.map(\.message), messages)
        XCTAssertTrue(rows.allSatisfy { $0.clarificationAnswers.isEmpty })
    }

    func testStructuredReplyDoesNotHideAnOwnedAssistantRowWithDifferentText() {
        let response = ChatMessage(role: .assistant, content: "Using the blue palette.")
        let assistantNote = child(.assistant, content: "I found a template.", of: response.id)
        var reply = child(.user, content: "Which accent?\nBlue", of: response.id)
        let answers = [VyronClarificationAnswer(question: "Which accent?", answer: "Blue")]
        reply.clarificationAnswers = answers

        let rows = VyronConversationTranscript(messages: [assistantNote, reply, response]).rows

        XCTAssertEqual(rows.map(\.message), [assistantNote, reply, response])
        XCTAssertEqual(rows.map(\.clarificationAnswers), [[], answers, []])
    }

    private func assertLegacyRowsStaySeparate(
        prompt: String, reply: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let response = ChatMessage(role: .assistant, content: "Done.")
        let messages = [
            child(.assistant, content: prompt, of: response.id),
            child(.user, content: reply, of: response.id),
            response
        ]
        let rows = VyronConversationTranscript(messages: messages).rows

        XCTAssertEqual(rows.map(\.message), messages, file: file, line: line)
        XCTAssertTrue(rows.allSatisfy { $0.clarificationAnswers.isEmpty }, file: file, line: line)
    }

    private func child(_ role: VyronChatMessageRole, content: String, of owner: UUID) -> ChatMessage {
        var message = ChatMessage(role: role, content: content)
        message.parentResponseID = owner
        return message
    }
}
