import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronLinkedChatDeliveryTests: XCTestCase {
    func testChatProviderReceivesVisibleTranscriptFromPlainSentenceLink() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.model.skillContextLoader = { _ in .empty }
        let source = sourceChat()
        test.model.conversations = [source]
        let link = try XCTUnwrap(VyronChatDeepLink(conversationID: source.id).url)
        test.send("Explain the saved discussion at \(link.absoluteString).")
        try await waitUntil { await test.provider.requests.count == 1 }
        let requests = await test.provider.requests
        let content = try XCTUnwrap(requests.first).map(\.content).joined(separator: "\n")
        XCTAssertTrue(content.contains("SAVED_VISIBLE_EVIDENCE"))
        XCTAssertTrue(content.contains("untrusted historical evidence"))
        XCTAssertFalse(content.contains("PRIVATE_"))
        await test.provider.complete(0, answer: "The saved conversation is available as reference.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testSideChatCanExplicitlyReferenceMainChatAfterItsOriginalSnapshot() async throws {
        let test = try VyronSideChatTestHarness()
        let model = test.model
        let mainID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: mainID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        let index = try XCTUnwrap(model.conversations.firstIndex { $0.id == mainID })
        let latest = ChatMessage(role: "assistant", content: "NEW_LINKED_VISIBLE_EVIDENCE")
        model.conversations[index].messages.append(latest)
        model.conversations[index].contextByMessageID = [latest.id.uuidString: "PRIVATE_FILE_CONTEXT"]
        model.conversations[index].queuedMessages = [VyronQueuedMessage(content: "PRIVATE_QUEUED_DRAFT")]
        let link = try XCTUnwrap(VyronChatDeepLink(conversationID: mainID).url)
        session.draft = "Compare the latest discussion in [main](\(link.absoluteString))."
        session.send()
        try await test.waitUntil { await test.provider.requests.count == 1 }
        let requests = await test.provider.requests
        let content = try XCTUnwrap(requests.first).messages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(content.contains("NEW_LINKED_VISIBLE_EVIDENCE"))
        XCTAssertTrue(content.contains("Keep the original task and its evidence intact."))
        XCTAssertFalse(content.contains("PRIVATE_"))
        XCTAssertEqual(model.selectedConversationID, mainID)
        await test.provider.complete(1, answer: "Compared the saved text.")
        try await test.waitUntil { !session.isGenerating }
        let saved = try XCTUnwrap(model.conversations.first { $0.id == sideID })
        XCTAssertTrue(saved.contextByMessageID?.values.contains {
            $0.contains("NEW_LINKED_VISIBLE_EVIDENCE")
        } == true)
        await test.cleanUp()
    }

    func testWorkAndPlanSteeringCaptureLinkedTranscriptBeforeAsyncSkillLoading() async throws {
        for mode in [ComposerMode.agent, .plan] {
            let test = VyronQueueTestHarness()
            defer { test.cleanUp() }
            let project = test.directory.appendingPathComponent("Project", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            await test.model.loadWorkspace(project)
            let response = ChatMessage(role: "assistant", content: "Current response")
            var current = Conversation(title: "Current", workspacePath: project.path)
            current.mode = mode.rawValue
            current.messages = [response]
            let source = sourceChat()
            test.model.conversations = [current, source]
            test.model.selectedConversationID = current.id
            test.model.composer.mode = mode
            let generation = UUID()
            let identity = test.model.beginTestForegroundResponse(generationID: generation)
            let inbox = VyronSteeringInbox()
            let steering = VyronForegroundSteering(inbox: inbox, skills: VyronSkillResourceTools(commands: []))
            test.model.foregroundRun.start(identity, route: .steerableDevelopment(steering)) {}
            let loader = VyronSkillContextTestLoader()
            test.model.skillContextLoader = { try await loader.load($0) }
            let link = try XCTUnwrap(VyronChatDeepLink(conversationID: source.id).url)
            let prompt = "Use the saved evidence at \(link.absoluteString)."
            test.send(prompt)
            let queuedID = try XCTUnwrap(test.model.queuedMessages.last?.id)
            test.model.steerQueuedMessage(queuedID)
            try await waitUntil { await loader.requests.count == 1 }
            test.model.conversations[1].messages[0].content = "LATER_SOURCE_CHANGE"
            await loader.complete(1, text: "CURRENT_SKILL_GUIDANCE")
            try await waitUntil { test.model.selectedConversation?.contextByMessageID?[queuedID.uuidString] != nil }
            let updates = await inbox.drain()
            let update = try XCTUnwrap(updates.first)
            XCTAssertTrue(update.content.contains("SAVED_VISIBLE_EVIDENCE"))
            XCTAssertTrue(update.content.contains("CURRENT_SKILL_GUIDANCE"))
            XCTAssertFalse(update.content.contains("LATER_SOURCE_CHANGE"))
            XCTAssertFalse(update.content.contains("PRIVATE_"))
            let savedContext = test.model.selectedConversation?.contextByMessageID?[queuedID.uuidString]
            XCTAssertTrue(savedContext?.contains("SAVED_VISIBLE_EVIDENCE") == true)
            XCTAssertTrue(savedContext?.contains("CURRENT_SKILL_GUIDANCE") == true)
            test.model.acknowledgeSteering(update, generationID: generation, conversationID: current.id)
            XCTAssertEqual(test.model.messages.first { $0.id == queuedID }?.content, prompt)
            XCTAssertEqual(test.model.selectedConversationID, current.id)
        }
    }

    private func sourceChat() -> Conversation {
        var source = Conversation(title: "Saved discussion", workspacePath: nil)
        source.mode = ComposerMode.chat.rawValue
        source.messages = [ChatMessage(role: "user", content: "SAVED_VISIBLE_EVIDENCE")]
        source.contextByMessageID = [source.messages[0].id.uuidString: "PRIVATE_FILE_CONTEXT"]
        source.queuedMessages = [VyronQueuedMessage(content: "PRIVATE_QUEUED_DRAFT")]
        return source
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Linked chat context did not reach the expected delivery boundary.")
        throw CancellationError()
    }
}
