import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatDeepLinkTests: XCTestCase {
    func testLinksRoundTripOnlyTheStableConversationIdentity() throws {
        let id = UUID()
        let link = VyronChatDeepLink(conversationID: id)
        let url = try XCTUnwrap(link.url)
        XCTAssertEqual(url.absoluteString, "vyron://chat/" + id.uuidString.lowercased())
        XCTAssertEqual(VyronChatDeepLink(url: url), link)

        for text in [
            "https://chat/\(id)", "vyron://other/\(id)", "vyron://chat/not-a-uuid",
            "vyron://chat/\(id)/extra", "vyron://chat/\(id)?send=do-something",
            "vyron://chat/\(id)#prompt", "vyron://user@chat/\(id)", "vyron://chat:42/\(id)"
        ] {
            XCTAssertNil(VyronChatDeepLink(url: try XCTUnwrap(URL(string: text))), text)
        }
    }

    func testOpeningKnownChatNavigatesWithoutSendingOrChangingItsHistory() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let first = conversation("First")
        var second = conversation("Second")
        second.isUnread = true
        test.model.conversations = [first, second]
        test.model.selectedConversationID = first.id
        test.model.registerSidebarConversation(first.id)
        test.model.registerSidebarConversation(second.id)
        XCTAssertTrue(test.model.saveHistory())
        let url = try XCTUnwrap(VyronChatDeepLink(conversationID: second.id).url)

        XCTAssertTrue(test.model.openChatDeepLink(url))
        XCTAssertEqual(test.model.selectedConversationID, second.id)
        XCTAssertEqual(test.model.selectedConversation?.messages, second.messages)
        XCTAssertNotEqual(test.model.selectedConversation?.isUnread, true)
        XCTAssertTrue(test.model.composer.draft.isEmpty)
        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testLinkDoesNotDiscardDraftOrQueueAndRejectsUnknownOrArchivedChat() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let first = conversation("First")
        let second = conversation("Second")
        test.model.conversations = [first, second]
        test.model.selectedConversationID = first.id
        test.model.registerSidebarConversation(first.id)
        test.model.registerSidebarConversation(second.id)
        let url = try XCTUnwrap(VyronChatDeepLink(conversationID: second.id).url)

        test.model.composer.draft = "Keep this draft"
        XCTAssertFalse(test.model.openChatDeepLink(url))
        XCTAssertEqual(test.model.selectedConversationID, first.id)
        XCTAssertEqual(test.model.composer.draft, "Keep this draft")
        test.model.composer.draft = ""
        test.model.conversations[0].queuedMessages = [VyronQueuedMessage(content: "Keep this update")]
        XCTAssertFalse(test.model.openChatDeepLink(url))
        XCTAssertEqual(test.model.conversations[0].queuedMessages?.first?.content, "Keep this update")
        test.model.conversations[0].queuedMessages = nil
        test.model.beginTestForegroundResponse()
        XCTAssertFalse(test.model.openChatDeepLink(url))
        test.model.foregroundRun.stop()

        XCTAssertTrue(test.model.changeSidebar { try $0.archiveConversations(ids: [second.id]) })
        XCTAssertFalse(test.model.openChatDeepLink(url))
        let unknown = try XCTUnwrap(VyronChatDeepLink(conversationID: UUID()).url)
        XCTAssertFalse(test.model.openChatDeepLink(unknown))
        XCTAssertEqual(test.model.selectedConversationID, first.id)
    }

    func testCopyActionsUseCapturedChatAndActualWorkingDirectory() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        var first = conversation("First")
        first.workspacePath = "/project/source folder"
        first.projectPath = "/project/sidebar identity"
        let second = conversation("Second")
        test.model.conversations = [first, second]
        test.model.selectedConversationID = first.id
        XCTAssertEqual(test.model.chatWorkingDirectory(for: first.id), first.workspacePath)
        XCTAssertEqual(
            test.model.chatDeepLink(for: first.id),
            VyronChatDeepLink(conversationID: first.id).url
        )
        test.model.selectedConversationID = second.id
        XCTAssertEqual(test.model.chatDeepLink(for: first.id), VyronChatDeepLink(conversationID: first.id).url)
        XCTAssertEqual(test.model.chatWorkingDirectory(for: first.id), first.workspacePath)
        XCTAssertNil(test.model.chatWorkingDirectory(for: second.id))
        XCTAssertEqual(test.model.selectedConversationID, second.id)
    }

    private func conversation(_ title: String) -> Conversation {
        var chat = Conversation(title: title, workspacePath: nil)
        chat.mode = ComposerMode.chat.rawValue
        chat.messages = [ChatMessage(role: "user", content: "Keep this history")]
        return chat
    }
}
