import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatTitleTests: XCTestCase {
    func testReferenceTitleCombinesSavedSubjectWithMeaningfulRequest() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = Conversation(title: "Fix Shift+Enter", workspacePath: nil)
        test.model.conversations = [source]
        let link = try XCTUnwrap(VyronChatDeepLink(conversationID: source.id).url).absoluteString
        for prompt in [
            link + " Explain this chat",
            "[earlier chat](" + link + ") Explain this chat",
            "<" + link.uppercased() + "> Explain this chat",
            "`" + link + "` Explain this chat",
            "vyron://chat/" + UUID().uuidString + " " + link + " Explain this chat"
        ] {
            XCTAssertEqual(test.model.initialConversationTitle(for: prompt), "Fix Shift+Enter · Explain this chat")
        }
        XCTAssertEqual(test.model.initialConversationTitle(for: link), source.title)
        XCTAssertEqual(test.model.initialConversationTitle(for: "Ordinary request\nwith context"),
                       "Ordinary request with context")
    }

    func testLongReferenceTitleReservesSpaceForBothSubjectAndRequest() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = Conversation(title: "Fix Shift+Enter " + String(repeating: "details ", count: 20), workspacePath: nil)
        test.model.conversations = [source]
        let link = try XCTUnwrap(VyronChatDeepLink(conversationID: source.id).url).absoluteString
        let title = test.model.initialConversationTitle(for: link + " Explain the final result and any remaining issues")
        XCTAssertTrue(title.hasPrefix("Fix Shift+Enter"))
        XCTAssertTrue(title.contains(" · Explain the final result"))
        XCTAssertFalse(title.contains("vyron://"))
        XCTAssertFalse(title.contains(source.id.uuidString.lowercased()))
        XCTAssertLessThanOrEqual(title.count, 54)
    }

    func testNewChatKeepsOriginalLinkedMessageWhileSavingReadableTitle() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.model.skillContextLoader = { _ in .empty }
        var source = Conversation(title: "Fix Shift+Enter", workspacePath: nil)
        source.messages = [ChatMessage(role: "assistant", content: "Shift+Enter now inserts a new line.")]
        test.model.conversations = [source]
        let link = try XCTUnwrap(VyronChatDeepLink(conversationID: source.id).url).absoluteString
        let prompt = link + " Explain this chat"
        test.send(prompt)
        for _ in 0..<500 {
            if await test.provider.requests.count == 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(test.model.selectedConversation?.title, "Fix Shift+Enter · Explain this chat")
        XCTAssertEqual(test.model.messages.first?.content, prompt)
        XCTAssertNotEqual(test.model.selectedConversationID, source.id)
        let request = await test.provider.requests.first
        XCTAssertTrue(request?.contains { $0.content.contains("Shift+Enter now inserts a new line.") } == true)
        await test.provider.complete(0, answer: "Explained the saved chat.")
    }
}
