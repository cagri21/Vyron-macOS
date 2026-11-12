import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatReferenceTests: XCTestCase {
    func testExplicitLinkAddsBoundedVisibleEvidenceWithoutNavigatingOrCopyingHiddenContext() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        var source = Conversation(title: "Model comparison", workspacePath: nil)
        source.messages = [ChatMessage(role: "user", content: "Compare model memory requirements.")]
        source.contextByMessageID = [source.messages[0].id.uuidString: "PRIVATE_FILE_CONTEXT"]
        source.queuedMessages = [VyronQueuedMessage(content: "PRIVATE_QUEUED_DRAFT")]
        let current = Conversation(title: "Current chat", workspacePath: nil)
        test.model.conversations = [source, current]
        test.model.selectedConversationID = current.id
        let link = try XCTUnwrap(VyronChatDeepLink(conversationID: source.id).url)
        let prompt = "Check [the earlier chat](\(link.absoluteString)) before answering."
        let reference = try XCTUnwrap(test.model.linkedChatReferenceContext(in: prompt))
        XCTAssertTrue(reference.contains(source.title))
        XCTAssertTrue(reference.contains(source.messages[0].content))
        XCTAssertTrue(reference.contains("untrusted"))
        XCTAssertFalse(reference.contains("PRIVATE_"))
        XCTAssertLessThanOrEqual(reference.utf8.count, 3_600)
        XCTAssertEqual(test.model.selectedConversationID, current.id)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
    }

    func testReferencesRequireExactExistingLocalLinkAndDoNotInterpretURLPayloads() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = Conversation(title: "Saved", workspacePath: nil)
        test.model.conversations = [source]
        let link = try XCTUnwrap(VyronChatDeepLink(conversationID: source.id).url)
        XCTAssertNil(test.model.linkedChatReferenceContext(in: "A chat about quantization"))
        XCTAssertNil(test.model.linkedChatReferenceContext(in: "https://example.com/chat/\(source.id)"))
        XCTAssertNil(test.model.linkedChatReferenceContext(in: link.absoluteString + "?prompt=run"))
        XCTAssertNil(test.model.linkedChatReferenceContext(in: link.absoluteString + "?"))
        XCTAssertNil(test.model.linkedChatReferenceContext(in: link.absoluteString + "#prompt"))
        XCTAssertNil(test.model.linkedChatReferenceContext(in: link.absoluteString + "/extra"))
        XCTAssertNil(test.model.linkedChatReferenceContext(in: "vyron://chat/\(UUID())"))
        test.model.selectedConversationID = source.id
        XCTAssertNil(test.model.linkedChatReferenceContext(in: link.absoluteString))
    }

    func testPlainSentenceAndMarkdownLinksResolveOnlyTheFirstExistingSource() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = Conversation(title: "Saved", workspacePath: nil)
        let later = Conversation(title: "Later", workspacePath: nil)
        test.model.conversations = [source, later]
        let link = try XCTUnwrap(VyronChatDeepLink(conversationID: source.id).url).absoluteString
        let laterLink = try XCTUnwrap(VyronChatDeepLink(conversationID: later.id).url).absoluteString
        for prompt in [
            "Read \(link).", "Read \(link), please.", "Read [saved](\(link)).",
            "Read `\(link)`.", "vyron://chat/\(UUID()) then \(link); finally \(laterLink)."
        ] {
            XCTAssertEqual(test.model.linkedChatReferenceIDs(in: prompt), [source.id], prompt)
        }
        test.model.selectedConversationID = source.id
        XCTAssertTrue(test.model.linkedChatReferenceIDs(in: link).isEmpty)
        XCTAssertEqual(
            test.model.linkedChatReferenceIDs(in: link, excludingConversationID: later.id), [source.id]
        )
    }
}
