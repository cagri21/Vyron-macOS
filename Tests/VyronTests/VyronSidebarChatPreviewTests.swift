import Foundation
import XCTest
@testable import Vyron

final class VyronSidebarChatPreviewTests: XCTestCase {
    func testDefaultPreviewKeepsFirstFiveChatsInSourceOrder() {
        let conversations = chats(count: 8)
        let originalIDs = conversations.map(\.id)

        let visible = VyronSidebarChatPreview.visibleChats(conversations, selectedID: nil, showsAll: false)

        XCTAssertEqual(visible.map(\.id), Array(originalIDs.prefix(5)))
        XCTAssertEqual(conversations.map(\.id), originalIDs)
    }

    func testSelectedChatBeyondCutoffReplacesFifthWithoutChangingSourceOrder() {
        let conversations = chats(count: 8)

        for selectedIndex in [5, 7] {
            let visible = VyronSidebarChatPreview.visibleChats(
                conversations,
                selectedID: conversations[selectedIndex].id,
                showsAll: false
            )

            XCTAssertEqual(visible.count, 5)
            XCTAssertEqual(
                visible.map(\.id),
                conversations.prefix(4).map(\.id) + [conversations[selectedIndex].id]
            )
        }
    }

    func testSelectionWithinPreviewOrOutsideGroupKeepsOriginalFive() {
        let conversations = chats(count: 8)
        let expectedIDs = conversations.prefix(5).map(\.id)
        let selections: [UUID?] = [nil, conversations[0].id, conversations[4].id, UUID()]

        for selection in selections {
            let visible = VyronSidebarChatPreview.visibleChats(
                conversations,
                selectedID: selection,
                showsAll: false
            )

            XCTAssertEqual(visible.map(\.id), expectedIDs)
        }
    }

    func testExpandedPreviewReturnsAllChatsInSourceOrder() {
        let conversations = chats(count: 8)

        for selection in [nil, conversations[7].id] {
            let visible = VyronSidebarChatPreview.visibleChats(
                conversations,
                selectedID: selection,
                showsAll: true
            )

            XCTAssertEqual(visible.map(\.id), conversations.map(\.id))
        }
    }

    func testEmptyAndShortGroupsReturnAllChats() {
        for count in [0, 3, 5] {
            let conversations = chats(count: count)
            let visible = VyronSidebarChatPreview.visibleChats(
                conversations,
                selectedID: conversations.last?.id,
                showsAll: false
            )

            XCTAssertEqual(visible.map(\.id), conversations.map(\.id))
        }
    }

    private func chats(count: Int) -> [Conversation] {
        (0..<count).map { Conversation(title: "Chat \($0)", workspacePath: "/Projects/Example") }
    }
}
