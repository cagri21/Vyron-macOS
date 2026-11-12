import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatOrganizationTests: XCTestCase {
    func testUnreadMarkerPersistsAndOpeningTheSameChatClearsIt() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let chat = Conversation(title: "Read later", workspacePath: nil)
        test.model.conversations = [chat]
        test.model.selectedConversationID = chat.id
        test.model.registerSidebarConversation(chat.id)
        XCTAssertTrue(test.model.markChatUnread(chat.id))
        let reopened = AppModel(historyDirectory: test.directory)
        XCTAssertEqual(reopened.conversations.first { $0.id == chat.id }?.isUnread, true)

        test.model.composer.draft = "Keep my draft"
        test.model.selectConversation(chat.id)
        XCTAssertNotEqual(test.model.selectedConversation?.isUnread, true)
        XCTAssertEqual(test.model.composer.draft, "Keep my draft")
        let readAgain = AppModel(historyDirectory: test.directory)
        XCTAssertNotEqual(readAgain.conversations.first { $0.id == chat.id }?.isUnread, true)
    }

    func testOldHistoryDecodesWithoutUnreadFieldAndUnreadActionUsesCapturedChat() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let first = Conversation(title: "First", workspacePath: nil)
        let second = Conversation(title: "Second", workspacePath: nil)
        let data = try JSONEncoder().encode(first)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "isUnread")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let restored = try JSONDecoder().decode(Conversation.self, from: legacyData)
        XCTAssertNil(restored.isUnread)
        test.model.conversations = [first, second]
        test.model.selectedConversationID = second.id
        test.model.composer.draft = "Keep selected work"
        XCTAssertTrue(test.model.markChatUnread(first.id))
        XCTAssertEqual(test.model.conversations[0].isUnread, true)
        XCTAssertNil(test.model.conversations[1].isUnread)
        XCTAssertEqual(test.model.selectedConversationID, second.id)
        XCTAssertEqual(test.model.composer.draft, "Keep selected work")
    }

    func testUnreadWriteFailureRollsBackMarker() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let chat = Conversation(title: "First", workspacePath: nil)
        test.model.conversations = [chat]
        test.model.selectedConversationID = chat.id
        XCTAssertTrue(test.model.saveHistory())
        let history = test.directory.appendingPathComponent("conversations.json")
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)
        XCTAssertFalse(test.model.markChatUnread(chat.id))
        XCTAssertNil(test.model.selectedConversation?.isUnread)
        try FileManager.default.removeItem(at: history)
        XCTAssertTrue(test.model.saveHistory())
    }

    func testSectionPlacementPersistsWithoutChangingProjectOrTranscript() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        var chat = Conversation(title: "Project work", workspacePath: "/project/source")
        chat.projectPath = "/project/identity"
        chat.messages = [ChatMessage(role: "user", content: "Keep this request")]
        test.model.conversations = [chat]
        test.model.selectedConversationID = chat.id
        test.model.registerSidebarConversation(chat.id)
        XCTAssertTrue(test.model.saveHistory())
        let parent = try XCTUnwrap(test.model.createSidebarFolder(name: "Projects"))
        let child = try XCTUnwrap(test.model.createSidebarFolder(name: "Later", parentID: parent))

        XCTAssertTrue(test.model.moveChatToSection(chat.id, folderID: child))
        XCTAssertEqual(test.model.chatSectionName(child), "Projects / Later")
        XCTAssertEqual(test.model.selectedConversation?.projectPath, chat.projectPath)
        XCTAssertEqual(test.model.selectedConversation?.workspacePath, chat.workspacePath)
        XCTAssertEqual(test.model.selectedConversation?.messages, chat.messages)
        let reopened = AppModel(historyDirectory: test.directory)
        XCTAssertEqual(reopened.sidebarState.sidebarOrganization.folderID(for: .conversation(chat.id)), child)
        XCTAssertFalse(test.model.moveChatToSection(chat.id, folderID: UUID()))
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization.folderID(for: .conversation(chat.id)), child)
        XCTAssertTrue(test.model.moveChatToSection(chat.id, folderID: nil))
        XCTAssertNil(test.model.sidebarState.sidebarOrganization.folderID(for: .conversation(chat.id)))
    }
}
