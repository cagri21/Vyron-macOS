import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronForegroundStopOwnershipTests: XCTestCase {
    func testStopUpdatesTheResponseThatStartedWorkWhileAnotherChatIsSelected() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let response = beginDevelopment(in: test.model)
        var other = Conversation(title: "Other chat", workspacePath: nil)
        other.messages = [ChatMessage(role: .assistant, content: "Keep this answer.")]
        test.model.conversations.append(other)
        test.model.selectedConversationID = other.id

        test.model.stopGeneration()

        let stopped = try XCTUnwrap(test.model.conversations.first { $0.id == response.conversationID })
        XCTAssertEqual(stopped.messages.first?.content, VyronStatusText.developmentStoppedReview)
        XCTAssertEqual(stopped.messages.first?.activity?.state, .stopped)
        XCTAssertEqual(test.model.selectedConversation?.messages.last?.content, "Keep this answer.")
    }

    func testQuitUpdatesTheOriginatingResponseBeforeLaterMessages() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let response = beginDevelopment(in: test.model)
        test.model.conversations[0].messages.append(ChatMessage(role: .user, content: "Keep this clarification."))

        await test.model.shutdownAsync()

        let stopped = try XCTUnwrap(test.model.conversations.first { $0.id == response.conversationID })
        XCTAssertEqual(stopped.messages.first?.id, response.messageID)
        XCTAssertEqual(stopped.messages.first?.content, VyronStatusText.developmentStoppedOnQuit)
        XCTAssertEqual(stopped.messages.first?.activity?.state, .stopped)
        XCTAssertEqual(stopped.messages.last?.content, "Keep this clarification.")
    }

    private func beginDevelopment(in model: AppModel) -> VyronResponseIdentity {
        let message = ChatMessage(role: .assistant, content: "Partial response", activity: ResponseActivity())
        var conversation = Conversation(title: "Project task", workspacePath: nil)
        conversation.messages = [message]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        let response = VyronResponseIdentity(
            generationID: UUID(), conversationID: conversation.id, messageID: message.id
        )
        model.foregroundRun.begin(response, balanceConnectionID: nil)
        model.foregroundRun.beginDevelopment(response)
        return response
    }
}
