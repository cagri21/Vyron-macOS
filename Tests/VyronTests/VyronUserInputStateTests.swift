import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronUserInputStateTests: XCTestCase {
    private var directory: URL!
    private var model: AppModel!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model = AppModel(historyDirectory: directory)
        var conversation = Conversation(title: "Question test", workspacePath: nil)
        let assistant = ChatMessage(role: "assistant", content: "", activity: ResponseActivity())
        conversation.messages = [ChatMessage(role: "user", content: "Make a change"), assistant]
        conversation.queuedMessages = [VyronQueuedMessage(content: "A queued follow-up")]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.beginTestForegroundResponse()
        model.composer.draft = "An unrelated draft"
    }

    override func tearDown() async throws {
        model.stopGeneration()
        model = nil
        try FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testAnswerResumesSameRequestAndPersistsExchangeBeforeActiveResponse() async throws {
        let request = makeRequest()
        let generationID = try XCTUnwrap(model.foregroundRun.activeGeneration)
        let responseID = try XCTUnwrap(model.foregroundRun.activeResponse?.messageID)
        let waiting = Task { try await model.requestDevelopmentUserInput(request, generationID: generationID) }
        try await waitForRequest(request.id)
        let response = VyronUserInputResponse(requestID: request.id, answers: [
            VyronUserInputAnswer(questionID: "scope", value: "Only this feature")
        ])
        model.respondToUserInput(response)
        let received = try await waiting.value
        XCTAssertEqual(received.requestID, request.id)
        XCTAssertEqual(received.answers.first?.value, "Only this feature")
        XCTAssertNil(model.interactions.pendingUserInput)
        XCTAssertEqual(model.foregroundRun.activeGeneration, generationID)
        XCTAssertEqual(model.composer.draft, "An unrelated draft")
        XCTAssertEqual(model.queuedMessages.map(\.content), ["A queued follow-up"])
        XCTAssertEqual(model.messages.map(\.role), ["user", "assistant", "user", "assistant"])
        XCTAssertEqual(model.messages.last?.id, responseID)
        XCTAssertTrue(model.messages[1].content.contains("Which scope?"))
        XCTAssertTrue(model.messages[2].content.contains("Only this feature"))
        let reopened = AppModel(historyDirectory: directory)
        XCTAssertEqual(reopened.conversations.first?.messages[2].content, model.messages[2].content)
        XCTAssertEqual(reopened.conversations.first?.messages.last?.id, responseID)
    }

    func testStaleAndIncompleteAnswersLeaveCurrentRequestWaiting() async throws {
        let request = makeRequest()
        let generationID = try XCTUnwrap(model.foregroundRun.activeGeneration)
        let waiting = Task { try await model.requestDevelopmentUserInput(request, generationID: generationID) }
        try await waitForRequest(request.id)
        model.respondToUserInput(VyronUserInputResponse(requestID: UUID(), answers: [
            VyronUserInputAnswer(questionID: "scope", value: "Stale")
        ]))
        model.respondToUserInput(VyronUserInputResponse(requestID: request.id, answers: []))
        model.respondToUserInput(VyronUserInputResponse(requestID: request.id, answers: [
            VyronUserInputAnswer(questionID: "scope", value: " \n ")
        ]))
        XCTAssertEqual(model.interactions.pendingUserInput?.id, request.id)
        model.respondToUserInput(VyronUserInputResponse(requestID: request.id, answers: [
            VyronUserInputAnswer(questionID: "scope", value: "Current")
        ]))
        let received = try await waiting.value
        XCTAssertEqual(received.answers.first?.value, "Current")
    }

    func testSkipResumesSameTaskAndPersistsPartialAnswersWithoutChangingComposer() async throws {
        let request = VyronUserInputRequest(questions: [
            VyronUserInputQuestion(id: "scope", question: "Which scope?"),
            VyronUserInputQuestion(id: "style", question: "Which style?")
        ])
        let generationID = try XCTUnwrap(model.foregroundRun.activeGeneration)
        let responseID = try XCTUnwrap(model.foregroundRun.activeResponse?.messageID)
        let waiting = Task { try await model.requestDevelopmentUserInput(request, generationID: generationID) }
        try await waitForRequest(request.id)
        var draft = VyronUserInputDraft()
        draft.setValue("Only this feature", for: "scope")
        let skippedAnswer = "Skip this question and use your best judgment."
        model.respondToUserInput(try XCTUnwrap(draft.responseSkippingUnanswered(
            to: request, skippedAnswer: skippedAnswer
        )))
        let received = try await waiting.value
        XCTAssertEqual(received.requestID, request.id)
        XCTAssertEqual(received.answers.map(\.value), ["Only this feature", skippedAnswer])
        XCTAssertNil(model.interactions.pendingUserInput)
        XCTAssertEqual(model.foregroundRun.activeGeneration, generationID)
        XCTAssertEqual(model.foregroundRun.activeResponse?.messageID, responseID)
        XCTAssertEqual(model.composer.draft, "An unrelated draft")
        XCTAssertEqual(model.queuedMessages.map(\.content), ["A queued follow-up"])
        XCTAssertTrue(model.messages[2].content.contains("Only this feature"))
        XCTAssertTrue(model.messages[2].content.contains(skippedAnswer))
        let reopened = AppModel(historyDirectory: directory)
        XCTAssertEqual(reopened.conversations.first?.messages[2].content, model.messages[2].content)
        XCTAssertEqual(reopened.conversations.first?.messages.last?.id, responseID)
    }

    func testStopCancelsPendingQuestionAndKeepsDraft() async throws {
        let request = makeRequest()
        let generationID = try XCTUnwrap(model.foregroundRun.activeGeneration)
        let waiting = Task { try await model.requestDevelopmentUserInput(request, generationID: generationID) }
        try await waitForRequest(request.id)
        model.stopGeneration()
        do {
            _ = try await waiting.value
            XCTFail("A stopped question must cancel its suspended tool")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(model.interactions.pendingUserInput)
        XCTAssertEqual(model.composer.draft, "An unrelated draft")
    }

    func testSwitchingConversationCancelsQuestionAndIgnoresLateAnswer() async throws {
        let request = makeRequest()
        let generationID = try XCTUnwrap(model.foregroundRun.activeGeneration)
        let waiting = Task { try await model.requestDevelopmentUserInput(request, generationID: generationID) }
        try await waitForRequest(request.id)
        let other = Conversation(title: "Another chat", workspacePath: nil)
        model.conversations.append(other)
        model.selectConversation(other.id)
        do {
            _ = try await waiting.value
            XCTFail("Leaving the chat must cancel its question")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        model.respondToUserInput(VyronUserInputResponse(requestID: request.id, answers: [
            VyronUserInputAnswer(questionID: "scope", value: "Too late")
        ]))
        XCTAssertNil(model.interactions.pendingUserInput)
        XCTAssertEqual(model.selectedConversationID, other.id)
        XCTAssertTrue(model.messages.isEmpty)
    }

    func testTaskCancellationCannotClearAReplacementQuestion() async throws {
        let first = makeRequest()
        let generationID = try XCTUnwrap(model.foregroundRun.activeGeneration)
        let waiting = Task { try await model.requestDevelopmentUserInput(first, generationID: generationID) }
        try await waitForRequest(first.id)
        waiting.cancel()
        let replacement = makeRequest()
        let replacing = Task {
            try await model.requestDevelopmentUserInput(replacement, generationID: generationID)
        }
        try await waitForRequest(replacement.id)
        do {
            _ = try await waiting.value
            XCTFail("A canceled waiter must finish with cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        model.respondToUserInput(VyronUserInputResponse(requestID: first.id, answers: [
            VyronUserInputAnswer(questionID: "scope", value: "Old response")
        ]))
        XCTAssertEqual(model.interactions.pendingUserInput?.id, replacement.id)
        model.respondToUserInput(VyronUserInputResponse(requestID: replacement.id, answers: [
            VyronUserInputAnswer(questionID: "scope", value: "New response")
        ]))
        let received = try await replacing.value
        XCTAssertEqual(received.answers.first?.value, "New response")
    }

    private func makeRequest() -> VyronUserInputRequest {
        VyronUserInputRequest(questions: [VyronUserInputQuestion(id: "scope", question: "Which scope?")])
    }

    private func waitForRequest(_ requestID: UUID) async throws {
        for _ in 0..<100 {
            if model.interactions.pendingUserInput?.id == requestID { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The question did not become available")
        throw NSError(domain: "VyronUserInputStateTests", code: 1)
    }
}
