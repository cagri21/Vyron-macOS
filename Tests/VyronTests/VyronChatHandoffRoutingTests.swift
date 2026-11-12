import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatHandoffRoutingTests: XCTestCase {
    func testSendOpensChooserAndPreservesExactDraftWithoutStartingInference() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = installFixture(test)
        let prompt = "  Move this request to iOS-Study  "
        test.model.composer.draft = prompt
        test.model.send()
        XCTAssertEqual(test.model.handoff.chatHandoffPresentation?.sourceID, source.id)
        XCTAssertEqual(test.model.handoff.chatHandoffPresentation?.destination?.projectPath, test.directory.path)
        XCTAssertEqual(test.model.composer.draft, prompt)
        XCTAssertEqual(test.model.selectedConversationID, source.id)
        XCTAssertEqual(test.model.conversations.count, 1)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        test.model.handoff.chatHandoffPresentation = nil
        XCTAssertEqual(test.model.composer.draft, prompt)
    }

    func testUnknownDestinationRequiresChoiceAndCurrentProjectDoesNotSelectAnotherProject() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = installFixture(test)
        test.model.composer.draft = "Move this request to another project called Unknown"
        XCTAssertTrue(test.model.routeChatHandoffIfRequested())
        XCTAssertTrue(test.model.handoff.chatHandoffPresentation?.requiresDestinationSelection == true)
        XCTAssertNil(test.model.handoff.chatHandoffPresentation?.destination)
        test.model.handoff.chatHandoffPresentation = nil
        test.model.conversations[0].projectPath = test.directory.path
        test.model.composer.draft = "Move this request to iOS-Study"
        XCTAssertFalse(test.model.routeChatHandoffIfRequested())
        XCTAssertNil(test.model.handoff.chatHandoffPresentation)
        XCTAssertEqual(test.model.selectedConversationID, source.id)
    }

    func testPreparedDestinationDraftDoesNotReopenChooserAndUnrelatedDraftCannotUseBypass() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = installFixture(test)
        let prompt = "Move this request to iOS-Study"
        test.model.composer.draft = prompt
        test.model.prepareChatHandoffSend(destinationID: source.id, request: prompt)
        XCTAssertFalse(test.model.routeChatHandoffIfRequested())
        test.model.composer.draft = "Send this task to iOS-Study"
        XCTAssertTrue(test.model.routeChatHandoffIfRequested())
        XCTAssertEqual(test.model.handoff.chatHandoffPresentation?.initialRequest, test.model.composer.draft)
    }

    private func installFixture(_ test: VyronQueueTestHarness) -> Conversation {
        let source = Conversation(title: "Source", workspacePath: nil)
        test.model.conversations = [source]
        test.model.selectedConversationID = source.id
        test.model.registerSidebarConversation(source.id)
        _ = test.model.changeSidebar {
            try $0.updateProject(path: test.directory.path, name: "iOS-Study", sourceFolders: [test.directory.path])
        }
        return source
    }
}
