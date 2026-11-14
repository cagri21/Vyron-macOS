import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronApplicationAttachmentConversationTests: XCTestCase {
    func testApplicationOnlySendPersistsLocalReferenceAndSendsNameToProvider() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronScreenshotTestProvider()
        test.select(test.profile(), provider: provider)
        let application = VyronApplicationAttachment(
            name: "Penpot Desktop.app", path: "/Applications/Penpot Desktop.app"
        )
        test.model.composerAttachments.applications = [application]
        XCTAssertTrue(test.model.canSend)

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertTrue(test.model.composerAttachments.applications.isEmpty)
        XCTAssertEqual(test.model.messages.first?.applicationAttachments, [application])
        XCTAssertNil(test.model.errorMessage)
        let requests = await provider.receivedMessages
        let request = try XCTUnwrap(requests.first)
        let prompt = try XCTUnwrap(request.first(where: { $0.conversationRole == .user }))
        XCTAssertTrue(prompt.content.contains(application.name))
        XCTAssertFalse(prompt.content.contains(application.path))
        XCTAssertNil(prompt.applicationAttachments)

        let stored = try Data(contentsOf: test.directory.appendingPathComponent("conversations.json"))
        let restored = try JSONDecoder().decode([Conversation].self, from: stored)
        XCTAssertEqual(restored.first?.messages.first?.applicationAttachments, [application])
    }

    func testLegacyChatMessageDecodesWithoutApplicationReferences() throws {
        let legacy = """
            {"id":"00000000-0000-0000-0000-000000000001","role":"user","content":"Original message"}
            """

        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(legacy.utf8))

        XCTAssertEqual(message.content, "Original message")
        XCTAssertNil(message.applicationAttachments)
    }
}
