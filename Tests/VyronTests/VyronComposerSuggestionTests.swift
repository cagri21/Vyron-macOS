import Foundation
import VyronCore
import XCTest
@testable import Vyron

@MainActor
final class VyronComposerSuggestionTests: XCTestCase {
    func testUsesFirstQuestionFromLatestCompletedAssistantAnswer() throws {
        try withModel { model in
            let answer = try XCTUnwrap(model.messages.last)

            XCTAssertEqual(model.composerSuggestion, VyronComposerSuggestion(
                messageID: answer.id,
                text: "How can I test the cache expiration?"
            ))
            XCTAssertEqual(model.messages.count, 2)
            XCTAssertEqual(model.composer.draft, "")
        }
    }

    func testDoesNotFallBackToEarlierAnswersWhenLatestMessageIsUserOrHasNoQuestions() throws {
        try withModel { model in
            model.conversations[0].messages.append(ChatMessage(role: "user", content: "A newer request"))
            XCTAssertNil(model.composerSuggestion)

            model.conversations[0].messages.append(answer(questions: nil))
            XCTAssertNil(model.composerSuggestion)

            model.conversations[0].messages[2] = answer(questions: ["  ", "A second question?"])
            model.conversations[0].messages.removeLast()
            XCTAssertNil(model.composerSuggestion)
        }
    }

    func testDoesNotOfferSuggestionsForUnfinishedStoppedFailedOrLegacyAnswers() throws {
        try withModel { model in
            for state in [ResponseActivity.State.working, .stopped, .failed] {
                model.conversations[0].messages[1] = answer(state: state)
                XCTAssertNil(model.composerSuggestion)
            }

            model.conversations[0].messages[1] = ChatMessage(
                role: "assistant",
                content: "A legacy response",
                suggestedQuestions: ["A follow-up?"]
            )
            XCTAssertNil(model.composerSuggestion)
        }
    }

    func testExistingDraftIncludingWhitespaceHidesHintAndCannotBeOverwritten() throws {
        try withModel { model in
            let suggestion = try XCTUnwrap(model.composerSuggestion)

            for draft in ["My own question", " ", "\n"] {
                model.composer.draft = draft

                XCTAssertNil(model.composerSuggestion)
                model.acceptComposerSuggestion(suggestion)
                XCTAssertEqual(model.composer.draft, draft)
            }
        }
    }

    func testAcceptingCurrentHintOnlyFillsDraftWithoutSending() throws {
        try withModel { model in
            let suggestion = try XCTUnwrap(model.composerSuggestion)
            let originalMessages = model.messages

            model.acceptComposerSuggestion(suggestion)

            XCTAssertEqual(model.composer.draft, suggestion.text)
            XCTAssertEqual(model.messages, originalMessages)
            XCTAssertFalse(model.foregroundRun.isGenerating)
            XCTAssertNil(model.foregroundRun.activeGeneration)
            XCTAssertNil(model.composerSuggestion)
        }
    }

    func testRejectsForgedQuestionAlternateQuestionAndWrongMessageIdentity() throws {
        try withModel { model in
            let suggestion = try XCTUnwrap(model.composerSuggestion)
            let forged = [
                VyronComposerSuggestion(messageID: UUID(), text: suggestion.text),
                VyronComposerSuggestion(messageID: suggestion.messageID, text: "An invented question?"),
                VyronComposerSuggestion(messageID: suggestion.messageID, text: "Can I change the cache duration?")
            ]

            for candidate in forged {
                model.acceptComposerSuggestion(candidate)
                XCTAssertEqual(model.composer.draft, "")
            }
        }
    }

    func testRejectsStaleHintAfterNewAnswerOrConversationSwitch() throws {
        try withModel { model in
            let original = try XCTUnwrap(model.composerSuggestion)
            model.conversations[0].messages.append(answer())
            model.acceptComposerSuggestion(original)
            XCTAssertEqual(model.composer.draft, "")
            XCTAssertNotEqual(model.composerSuggestion?.messageID, original.messageID)

            let next = try XCTUnwrap(model.composerSuggestion)
            var otherConversation = Conversation(title: "Other chat", workspacePath: nil)
            otherConversation.messages = [answer()]
            model.conversations.append(otherConversation)
            model.selectedConversationID = otherConversation.id
            model.acceptComposerSuggestion(next)
            XCTAssertEqual(model.composer.draft, "")
            XCTAssertEqual(model.composerSuggestion?.messageID, otherConversation.messages.last?.id)
        }
    }

    func testBusyAndShutdownStatesHideHintAndRejectPreviouslyVisibleSuggestion() throws {
        try withModel { model in
            let suggestion = try XCTUnwrap(model.composerSuggestion)
            let busyStates: [ReferenceWritableKeyPath<AppModel, Bool>] = [
                \.computerWork.isComputerWorkActive,
                \.isRunningScheduledTask,
                \.isShuttingDown
            ]

            for state in busyStates {
                model[keyPath: state] = true
                XCTAssertNil(model.composerSuggestion)
                model.acceptComposerSuggestion(suggestion)
                XCTAssertEqual(model.composer.draft, "")
                model[keyPath: state] = false
                XCTAssertEqual(model.composerSuggestion, suggestion)
            }

            let response = model.beginTestForegroundResponse()
            XCTAssertNil(model.composerSuggestion)
            model.acceptComposerSuggestion(suggestion)
            XCTAssertEqual(model.composer.draft, "")
            model.foregroundRun.complete(response.generationID)
            XCTAssertEqual(model.composerSuggestion, suggestion)

            let development = model.beginTestForegroundResponse()
            model.foregroundRun.beginDevelopment(development)
            model.foregroundRun.start(development) {}
            XCTAssertTrue(model.foregroundRun.stop())
            XCTAssertNil(model.composerSuggestion)
            model.acceptComposerSuggestion(suggestion)
            XCTAssertEqual(model.composer.draft, "")
        }
    }

    func testQueueEditingHidesHintEvenWhenEditedDraftIsEmpty() throws {
        try withModel { model in
            let suggestion = try XCTUnwrap(model.composerSuggestion)
            model.composer.editingQueuedMessageID = UUID()

            XCTAssertNil(model.composerSuggestion)
            model.acceptComposerSuggestion(suggestion)
            XCTAssertEqual(model.composer.draft, "")

            model.composer.editingQueuedMessageID = nil
            XCTAssertEqual(model.composerSuggestion, suggestion)
        }
    }

    func testVoiceCaptureAndSpeechHideHintAndRejectPreviouslyVisibleSuggestion() throws {
        try withModel { model in
            let suggestion = try XCTUnwrap(model.composerSuggestion)

            model.voice.toggleDictation()
            XCTAssertTrue(model.voice.isActive)
            XCTAssertNil(model.composerSuggestion)
            model.acceptComposerSuggestion(suggestion)
            XCTAssertEqual(model.composer.draft, "")
            model.voice.end()
            XCTAssertEqual(model.composerSuggestion, suggestion)

            model.voice.previewVoice()
            XCTAssertEqual(model.voice.phase, .speaking)
            XCTAssertNil(model.composerSuggestion)
            model.acceptComposerSuggestion(suggestion)
            XCTAssertEqual(model.composer.draft, "")
        }
    }

    private func answer(
        questions: [String]? = ["How can I test the cache expiration?", "Can I change the cache duration?"],
        state: ResponseActivity.State = .completed
    ) -> ChatMessage {
        var activity = ResponseActivity()
        if state != .working { activity.finish(state) }
        return ChatMessage(
            role: "assistant",
            content: "The cache expires after one minute.",
            activity: activity,
            suggestedQuestions: questions
        )
    }

    private func withModel(_ body: (AppModel) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronComposerSuggestionTests-\(UUID())")
        let voice = VyronVoiceModel(service: VyronSpeechTestService())
        let model = AppModel(historyDirectory: directory, voice: voice)
        defer {
            model.voice.end()
            if FileManager.default.fileExists(atPath: directory.path) {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: directory))
            }
        }
        var conversation = Conversation(title: "Cache", workspacePath: nil)
        conversation.messages = [ChatMessage(role: "user", content: "Explain cache expiration"), answer()]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id

        try body(model)
    }
}
