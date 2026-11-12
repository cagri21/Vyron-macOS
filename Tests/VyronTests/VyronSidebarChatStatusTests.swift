import Foundation
import XCTest
@testable import Vyron
import VyronCore

final class VyronSidebarChatStatusTests: XCTestCase {
    func testLatestFailedResponseAppearsForPinnedAndUnpinnedChats() {
        var conversation = Conversation(title: "Any task title", workspacePath: "/Projects/Example")
        conversation.messages = [
            ChatMessage(role: "user", content: "Make a change"),
            response(.failed, content: "Partial answer without an error keyword")
        ]

        for isPinned in [false, true] {
            let chat = VyronSidebarChat(conversation: conversation, isPinned: isPinned, showsProject: false)
            XCTAssertTrue(chat.hasFailedResponse)
        }
    }

    func testNewResponseClearsEarlierFailureForEveryNonfailedState() {
        for state in [ResponseActivity.State.working, .completed, .stopped] {
            let chat = chat(messages: [response(.failed), response(state)])
            XCTAssertFalse(chat.hasFailedResponse, "Latest response state: \(state)")
        }

        let legacyReply = ChatMessage(role: "assistant", content: "Response failed is only quoted text")
        XCTAssertFalse(chat(messages: [response(.failed), legacyReply]).hasFailedResponse)
    }

    func testMessagesFromOtherRolesDoNotReplaceLatestResponseStatus() {
        let failedReply = response(.failed)
        let followUp = ChatMessage(role: "user", content: "Try again")
        let toolMessage = ChatMessage(role: "tool", content: "Recorded output")

        XCTAssertTrue(chat(messages: [failedReply, followUp, toolMessage]).hasFailedResponse)
        XCTAssertFalse(chat(messages: [response(.completed), toolMessage]).hasFailedResponse)
    }

    func testChatsWithoutAssistantResponsesHaveNoFailureStatus() {
        XCTAssertFalse(chat(messages: []).hasFailedResponse)
        XCTAssertFalse(chat(messages: [ChatMessage(role: "user", content: "Response failed")]).hasFailedResponse)
    }

    func testFailureStatusSurvivesConversationHistoryRoundTrip() throws {
        let original = chat(messages: [response(.failed, content: "Saved partial work")])
        let data = try JSONEncoder().encode(original.conversation)
        let reopened = try JSONDecoder().decode(Conversation.self, from: data)
        let restored = VyronSidebarChat(conversation: reopened, isPinned: false, showsProject: true)

        XCTAssertEqual(reopened.id, original.conversation.id)
        XCTAssertEqual(reopened.messages, original.conversation.messages)
        XCTAssertTrue(restored.hasFailedResponse)
    }

    private func response(_ state: ResponseActivity.State, content: String = "") -> ChatMessage {
        var activity = ResponseActivity()
        if state != .working { activity.finish(state) }
        return ChatMessage(role: "assistant", content: content, activity: activity)
    }

    private func chat(messages: [ChatMessage]) -> VyronSidebarChat {
        var conversation = Conversation(title: "Task", workspacePath: nil)
        conversation.messages = messages
        return VyronSidebarChat(conversation: conversation, isPinned: false, showsProject: false)
    }
}
