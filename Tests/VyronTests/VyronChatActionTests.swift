import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatActionTests: XCTestCase {
    func testRenamePinAndArchivePersistOnlyTheCapturedChat() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let first = chat("First")
        let second = chat("Second")
        test.model.conversations = [first, second]
        test.model.selectedConversationID = first.id
        test.model.registerSidebarConversation(first.id)
        test.model.registerSidebarConversation(second.id)
        XCTAssertTrue(test.model.saveHistory())

        let snapshot = try XCTUnwrap(test.model.chatActions(for: first.id))
        XCTAssertTrue(test.model.renameChat(snapshot.conversationID, title: "First rename"))
        XCTAssertTrue(test.model.toggleChatPin(snapshot.conversationID))
        XCTAssertTrue(test.model.sidebarState.sidebarOrganization.isPinned(.conversation(first.id)))
        test.model.selectConversation(second.id)
        XCTAssertTrue(test.model.renameChat(snapshot.conversationID, title: "  Renamed chat  "))
        XCTAssertTrue(test.model.toggleChatPin(snapshot.conversationID))
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.isPinned(.conversation(first.id)))
        XCTAssertTrue(test.model.toggleChatPin(snapshot.conversationID))
        XCTAssertNotNil(test.model.chatExport(for: snapshot.conversationID))
        XCTAssertEqual(test.model.selectedConversation?.title, second.title)
        test.model.composer.draft = "Keep the selected chat's draft"
        XCTAssertTrue(test.model.archiveChat(first.id))
        XCTAssertEqual(test.model.selectedConversationID, second.id)
        XCTAssertEqual(test.model.composer.draft, "Keep the selected chat's draft")
        XCTAssertTrue(test.model.sidebarState.sidebarOrganization.isConversationArchived(first.id))
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.isConversationArchived(second.id))
        XCTAssertEqual(test.model.conversations.first { $0.id == first.id }?.messages, first.messages)
        XCTAssertNil(test.model.chatActions(for: first.id))

        let reopened = AppModel(historyDirectory: test.directory)
        XCTAssertEqual(reopened.conversations.first { $0.id == first.id }?.title, "Renamed chat")
        XCTAssertEqual(reopened.conversations.first { $0.id == second.id }?.title, "Second")
        XCTAssertTrue(reopened.sidebarState.sidebarOrganization.isPinned(.conversation(first.id)))
        XCTAssertTrue(reopened.sidebarState.sidebarOrganization.isConversationArchived(first.id))
        XCTAssertEqual(reopened.conversations.count, 2)
    }

    func testContinueUsesUnselectedSourceAndProtectsBothChatsPendingWork() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        var source = chat("Source")
        source.messages[0].content = "The captured source request"
        let current = chat("Current")
        test.model.conversations = [source, current]
        test.model.selectedConversationID = current.id
        test.model.registerSidebarConversation(source.id)
        test.model.registerSidebarConversation(current.id)
        test.model.composer.draft = "Keep current work"
        XCTAssertNil(test.model.continueChat(source.id, in: .chat))
        XCTAssertEqual(test.model.composer.draft, "Keep current work")
        test.model.composer.draft = ""
        test.model.conversations[0].queuedMessages = [VyronQueuedMessage(content: "Pending source update")]
        XCTAssertFalse(try XCTUnwrap(test.model.chatActions(for: source.id)).canContinue)
        XCTAssertFalse(test.model.archiveChat(source.id))
        XCTAssertNil(test.model.continueChat(source.id, in: .chat))
        test.model.conversations[0].queuedMessages = nil

        let forkID = try XCTUnwrap(test.model.continueChat(source.id, in: .chat))
        let fork = try XCTUnwrap(test.model.conversations.first { $0.id == forkID })
        XCTAssertEqual(fork.messages.map(\.content), source.messages.map(\.content))
        XCTAssertEqual(test.model.selectedConversationID, forkID)
        XCTAssertEqual(test.model.conversations.first { $0.id == current.id }?.messages, current.messages)
        XCTAssertEqual(test.model.conversations.first { $0.id == source.id }?.messages, source.messages)
    }

    func testArchivingUnselectedChatDoesNotStopSelectedResponse() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Keep this response running")
        try await waitUntil { await test.provider.requests.count == 1 }
        let selectedID = try XCTUnwrap(test.model.selectedConversationID)
        let unrelated = chat("Archive later")
        test.model.conversations.append(unrelated)
        test.model.registerSidebarConversation(unrelated.id)
        XCTAssertTrue(test.model.archiveChat(unrelated.id))
        XCTAssertEqual(test.model.selectedConversationID, selectedID)
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        let cancellations = await test.provider.cancellations
        XCTAssertEqual(cancellations, 0)
        await test.provider.complete(0, answer: "Finished normally")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.selectedConversation?.messages.last?.content, "Finished normally")
    }

    func testContinueCreatesIndependentLockedModeAndRemapsClarificationOwnershipAndContext() throws {
        for mode in [ComposerMode.chat, .agent] {
            let test = VyronQueueTestHarness()
            defer { test.cleanUp() }
            var original = chat("Original", mode: mode == .chat ? .agent : .chat)
            let response = try XCTUnwrap(original.messages.last)
            var question = ChatMessage(role: "assistant", content: "Which color?")
            question.parentResponseID = response.id
            var answer = ChatMessage(role: "user", content: "Which color?\nUse blue.")
            answer.parentResponseID = response.id
            let clarification = VyronClarificationAnswer(question: question.content, answer: "Use blue.")
            answer.clarificationAnswers = [clarification]
            original.messages.insert(contentsOf: [question, answer], at: 1)
            original.contextByMessageID = [original.messages[0].id.uuidString: "Internal file context"]
            test.model.conversations = [original]
            test.model.selectedConversationID = original.id
            test.model.composer.mode = mode == .chat ? .agent : .chat
            test.model.registerSidebarConversation(original.id)
            let selectedModel = test.model.modelSelection.selectedModel
            let settings = test.model.modelSelection.builtinModelSettings
            let folder = try XCTUnwrap(test.model.createSidebarFolder(name: "Saved work"))
            XCTAssertTrue(test.model.moveSidebarItem(.conversation(original.id), toFolder: folder))

            let forkID = try XCTUnwrap(test.model.continueChat(original.id, in: mode))
            let fork = try XCTUnwrap(test.model.selectedConversation)
            XCTAssertEqual(fork.id, forkID)
            XCTAssertNotEqual(fork.id, original.id)
            XCTAssertEqual(fork.mode, mode.rawValue)
            XCTAssertEqual(test.model.composer.mode, mode)
            XCTAssertTrue(test.model.isConversationModeLocked)
            XCTAssertEqual(fork.messages.map(\.content), original.messages.map(\.content))
            XCTAssertTrue(Set(fork.messages.map(\.id)).isDisjoint(with: original.messages.map(\.id)))
            XCTAssertEqual(fork.messages[1].parentResponseID, fork.messages.last?.id)
            XCTAssertEqual(fork.messages[2].parentResponseID, fork.messages.last?.id)
            XCTAssertEqual(fork.messages[2].clarificationAnswers, [clarification])
            XCTAssertEqual(fork.contextByMessageID, [fork.messages[0].id.uuidString: "Internal file context"])
            XCTAssertEqual(test.model.sidebarState.sidebarOrganization.folderID(for: .conversation(forkID)), folder)
            XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
            XCTAssertEqual(test.model.modelSelection.builtinModelSettings, settings)
            let storedOriginal = try XCTUnwrap(test.model.conversations.first { $0.id == original.id })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            XCTAssertEqual(try encoder.encode(storedOriginal), try encoder.encode(original))
            let reopened = AppModel(historyDirectory: test.directory)
            XCTAssertEqual(reopened.conversations.first { $0.id == forkID }?.messages, fork.messages)
            XCTAssertEqual(reopened.conversations.first { $0.id == original.id }?.mode, original.mode)
        }
    }

    func testActiveResponseAndUnsentDraftQueueOrEditPreventNavigatingActions() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Explain the current task.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let id = try XCTUnwrap(test.model.selectedConversationID)
        XCTAssertFalse(try XCTUnwrap(test.model.chatActions(for: id)).canContinue)
        XCTAssertFalse(test.model.archiveChat(id))
        XCTAssertNil(test.model.continueChat(id, in: .agent))
        XCTAssertTrue(test.model.renameChat(id, title: "Current task"))
        XCTAssertNotNil(test.model.chatExport(for: id))
        let cancellations = await test.provider.cancellations
        XCTAssertEqual(cancellations, 0)
        await test.provider.complete(0, answer: "The task is complete.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertTrue(try XCTUnwrap(test.model.chatActions(for: id)).canContinue)

        test.model.composer.draft = "Unsent user guidance"
        XCTAssertFalse(test.model.archiveChat(id))
        XCTAssertNil(test.model.continueChat(id, in: .agent))
        XCTAssertEqual(test.model.composer.draft, "Unsent user guidance")
        test.model.composer.draft = ""
        test.model.conversations[0].queuedMessages = [VyronQueuedMessage(content: "Queued follow-up")]
        XCTAssertFalse(test.model.archiveChat(id))
        XCTAssertNil(test.model.continueChat(id, in: .agent))
        test.model.conversations[0].queuedMessages = nil
        test.model.composer.editingQueuedMessageID = UUID()
        XCTAssertFalse(test.model.archiveChat(id))
        XCTAssertNil(test.model.continueChat(id, in: .agent))
        test.model.composer.editingQueuedMessageID = nil
        test.model.workspaceState.isLoadingWorkspace = true
        XCTAssertFalse(try XCTUnwrap(test.model.chatActions(for: id)).canContinue)
        test.model.workspaceState.isLoadingWorkspace = false
    }

    func testExportIncludesVisibleTranscriptAndAttachmentNamesWithoutInternalData() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        var original = chat("Visible title")
        original.messages[0].images = [VyronImageAttachment(
            name: "screen\nshot.png", mimeType: "image/png", data: Data("PRIVATE_IMAGE_BYTES".utf8)
        )]
        var activity = ResponseActivity()
        activity.record("PRIVATE_ACTIVITY", detail: "PRIVATE_TOOL_ARGUMENTS")
        original.messages[1].activity = activity
        original.messages.append(ChatMessage(role: "system", content: "PRIVATE_SYSTEM"))
        original.messages.append(ChatMessage(role: "tool", content: "PRIVATE_TOOL"))
        original.contextByMessageID = [original.messages[0].id.uuidString: "PRIVATE_FILE_CONTEXT"]
        original.queuedMessages = [VyronQueuedMessage(content: "PRIVATE_QUEUED_DRAFT")]
        test.model.conversations = [original]
        test.model.selectedConversationID = original.id

        let exported = try XCTUnwrap(test.model.chatExport(for: original.id))
        XCTAssertEqual(exported.text, exported.markdown)
        for text in [exported.markdown, exported.plainText] {
            XCTAssertTrue(text.contains(original.title))
            XCTAssertTrue(text.contains(original.messages[0].content))
            XCTAssertTrue(text.contains(original.messages[1].content))
            XCTAssertTrue(text.contains("screen shot.png"))
            XCTAssertFalse(text.contains("PRIVATE_"))
            XCTAssertFalse(text.contains(original.messages[0].id.uuidString))
        }
    }

    func testSidebarOrHistoryWriteFailureRollsBackForkRenameAndArchive() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let original = chat("Original")
        test.model.conversations = [original]
        test.model.selectedConversationID = original.id
        test.model.registerSidebarConversation(original.id)
        XCTAssertTrue(test.model.saveHistory())
        let organization = test.model.sidebarState.sidebarOrganization
        let history = test.directory.appendingPathComponent("conversations.json")
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)
        XCTAssertFalse(test.model.renameChat(original.id, title: "Cannot save"))
        XCTAssertNil(test.model.continueChat(original.id, in: .agent))
        XCTAssertEqual(test.model.conversations.count, 1)
        XCTAssertEqual(test.model.selectedConversation?.title, original.title)
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), organization)
        try FileManager.default.removeItem(at: history)
        XCTAssertTrue(test.model.saveHistory())
        let originalData = try Data(contentsOf: history)
        try Data("corrupt sidebar fixture".utf8).write(to: test.model.sidebarState.sidebarStore.fileURL)
        XCTAssertFalse(test.model.archiveChat(original.id))
        XCTAssertNil(test.model.continueChat(original.id, in: .agent))
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(test.model.selectedConversationID, original.id)
        XCTAssertEqual(try Data(contentsOf: history), originalData)
    }

    func testProjectOpeningAvailabilityIsBoundToSourceAndCapturedID() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = test.directory.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        var original = chat("Project chat")
        original.workspacePath = source.path
        original.projectPath = test.directory.appendingPathComponent("Sidebar owner").path
        test.model.conversations = [original]
        test.model.selectedConversationID = original.id
        XCTAssertEqual(test.model.chatProjectURL(for: original.id), source)
        test.model.selectedConversationID = UUID()
        XCTAssertEqual(test.model.chatProjectURL(for: original.id), source)
        test.model.conversations = []
        XCTAssertNil(test.model.chatProjectURL(for: original.id))
        XCTAssertFalse(test.model.openChatProjectInFinder(original.id))
        XCTAssertFalse(test.model.openChatProjectInXcode(original.id))
    }

    private func chat(_ title: String, mode: ComposerMode = .chat) -> Conversation {
        var conversation = Conversation(title: title, workspacePath: nil)
        conversation.mode = mode.rawValue
        conversation.messages = [
            ChatMessage(role: "user", content: "Create an iOS template app."),
            ChatMessage(role: "assistant", content: "The initial project files are ready.")
        ]
        return conversation
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The fixture response did not reach the expected state.")
        throw CancellationError()
    }
}
