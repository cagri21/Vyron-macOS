import Combine
import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatHandoffTests: XCTestCase {
    func testPreparationSavesSeparateReferenceAndPreservesSourceAndPlainRequest() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = sourceChat(test)
        let project = try addProject("Destination", to: test)
        let request = request(source: source, project: project)

        let transaction = try XCTUnwrap(test.model.prepareChatHandoff(request))
        let destination = try XCTUnwrap(test.model.conversations.first { $0.id == transaction.destination.id })

        XCTAssertEqual(destination.workspacePath, project.path)
        XCTAssertEqual(destination.sidebarProjectPath, project.path)
        XCTAssertEqual(destination.mode, ComposerMode.agent.rawValue)
        XCTAssertEqual(destination.messages.count, 1)
        XCTAssertEqual(destination.messages[0].role, "assistant")
        XCTAssertTrue(destination.messages[0].content.contains("Original source request"))
        XCTAssertFalse(destination.messages[0].content.contains(request.prompt))
        XCTAssertEqual(test.model.selectedConversationID, source.id)
        XCTAssertEqual(test.model.composer.draft, "")
        XCTAssertEqual(test.model.conversations.first { $0.id == source.id }?.messages, source.messages)
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization.folderID(for: .conversation(destination.id)), nil)

        let reopened = AppModel(historyDirectory: test.directory)
        XCTAssertEqual(reopened.conversations.first { $0.id == destination.id }?.messages, destination.messages)
        XCTAssertEqual(reopened.conversations.first { $0.id == source.id }?.messages, source.messages)
    }

    func testDestinationFilteringRejectsChatArchivedQueuedAndActiveConversations() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        _ = sourceChat(test)
        let project = try addProject("Destination", to: test)
        var work = Conversation(title: "Work", workspacePath: project.path)
        work.mode = ComposerMode.agent.rawValue
        var chat = work
        chat.id = UUID()
        chat.mode = ComposerMode.chat.rawValue
        var queued = work
        queued.id = UUID()
        queued.queuedMessages = [VyronQueuedMessage(content: "Pending request")]
        var archived = work
        archived.id = UUID()
        var active = work
        active.id = UUID()
        test.model.conversations += [work, chat, queued, archived, active]
        test.model.foregroundRun.begin(.init(
            generationID: UUID(),
            conversationID: active.id, messageID: UUID()
        ))
        XCTAssertTrue(test.model.changeSidebar { organization in
            for conversation in [work, chat, queued, archived, active] {
                organization.registerConversation(id: conversation.id)
            }
            try organization.archiveConversations(ids: [archived.id])
        })

        let selection = VyronChatHandoffSelection(projectPath: project.path, workspacePath: project.path)
        XCTAssertEqual(test.model.chatHandoffConversations(for: selection).map(\.id), [work.id])
    }

    func testSourceDraftMayTransferOnlyWhenItMatchesCapturedRequest() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = sourceChat(test)
        let presentation = VyronChatHandoffPresentation(sourceID: source.id, initialRequest: "Captured draft")
        test.model.composer.draft = "Other unsent work"
        XCTAssertFalse(test.model.canPrepareChatHandoff(presentation))
        test.model.composer.draft = "Captured draft"
        XCTAssertTrue(test.model.canPrepareChatHandoff(presentation))
        test.model.composer.draft = "  Captured draft\n"
        XCTAssertTrue(test.model.canPrepareChatHandoff(presentation))
        test.model.conversations[0].queuedMessages = [VyronQueuedMessage(content: "Keep this")]
        XCTAssertFalse(test.model.canPrepareChatHandoff(presentation))
        test.model.conversations[0].queuedMessages = nil
        test.model.foregroundRun.begin(.init(
            generationID: UUID(),
            conversationID: source.id, messageID: UUID()
        ))
        XCTAssertFalse(test.model.canPrepareChatHandoff(presentation))
    }

    func testUnselectedSourceHandoffPreservesCurrentChatAndRejectsItsUnsentDraft() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = sourceChat(test)
        let project = try addProject("Destination", to: test)
        let current = Conversation(title: "Current chat", workspacePath: nil)
        test.model.conversations.append(current)
        test.model.selectedConversationID = current.id
        let presentation = VyronChatHandoffPresentation(sourceID: source.id, initialRequest: "Current draft")
        test.model.composer.draft = "Current draft"
        XCTAssertFalse(test.model.canPrepareChatHandoff(presentation))
        XCTAssertEqual(test.model.composer.draft, "Current draft")
        test.model.composer.draft = ""
        test.model.conversations[0].queuedMessages = [VyronQueuedMessage(content: "Pending source update")]
        XCTAssertFalse(test.model.canPrepareChatHandoff(presentation))
        test.model.conversations[0].queuedMessages = nil

        let transaction = try XCTUnwrap(test.model.prepareChatHandoff(request(source: source, project: project)))
        XCTAssertTrue(transaction.destination.messages[0].content.contains("Original source request"))
        XCTAssertEqual(test.model.selectedConversationID, current.id)
        XCTAssertTrue(test.model.composer.draft.isEmpty)
        XCTAssertEqual(test.model.conversations.first { $0.id == source.id }?.messages, source.messages)
    }

    func testDefaultRequestUsesSubstantiveSourceGoalInsteadOfContinuationCommand() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = sourceChat(test)
        test.model.conversations[0].messages.append(ChatMessage(role: "user", content: "continue"))

        let request = test.model.chatHandoffDefaultRequest(for: VyronChatHandoffPresentation(sourceID: source.id))

        XCTAssertEqual(request, "Original source request")
    }

    func testHistoryFailureRollsBackDestinationAndSidebarRegistration() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = sourceChat(test)
        let project = try addProject("Destination", to: test)
        XCTAssertTrue(test.model.saveHistory())
        let organization = test.model.sidebarState.sidebarOrganization
        let history = test.directory.appendingPathComponent("conversations.json")
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)

        XCTAssertNil(test.model.prepareChatHandoff(request(source: source, project: project)))
        XCTAssertEqual(test.model.conversations.map(\.id), [source.id])
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), organization)
        XCTAssertEqual(test.model.selectedConversationID, source.id)
    }

    func testOpeningDestinationPreparesPlainDraftWithoutStartingWork() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = sourceChat(test)
        let project = try addProject("Destination", to: test)
        let request = request(source: source, project: project)

        let opened = await test.model.handOffChat(request)
        XCTAssertTrue(opened)
        XCTAssertEqual(test.model.composer.draft, request.prompt)
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, project.path)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, project.path)
        XCTAssertEqual(test.model.selectedConversation?.sidebarProjectPath, project.path)
        XCTAssertNotEqual(test.model.selectedConversationID, source.id)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        let requestCount = await test.provider.requests.count
        XCTAssertEqual(requestCount, 0)
    }

    func testRollbackDoesNotDiscardLaterConversationEdits() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = sourceChat(test)
        let project = try addProject("Destination", to: test)
        let transaction = try XCTUnwrap(test.model.prepareChatHandoff(request(source: source, project: project)))
        let index = try XCTUnwrap(test.model.conversations.firstIndex { $0.id == transaction.destination.id })
        test.model.conversations[index].messages.append(ChatMessage(role: "user", content: "Concurrent work"))

        test.model.restorePreparedChatHandoff(transaction)

        XCTAssertEqual(test.model.conversations[index].messages.last?.content, "Concurrent work")
        XCTAssertTrue(test.model.sidebarState.sidebarOrganization.contains(.conversation(transaction.destination.id)))
    }

    func testExistingDestinationReceivesReferenceAndRollbackRestoresItsHistory() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = sourceChat(test)
        let project = try addProject("Destination", to: test)
        var destination = Conversation(title: "Existing work", workspacePath: project.path)
        destination.mode = ComposerMode.agent.rawValue
        destination.isUnread = true
        destination.messages = [ChatMessage(role: "user", content: "Existing task")]
        test.model.conversations.append(destination)
        test.model.registerSidebarConversation(destination.id)
        let request = VyronChatHandoffRequest(
            source: VyronChatHandoffPresentation(sourceID: source.id),
            destination: VyronChatHandoffSelection(
                projectPath: project.path, workspacePath: project.path, conversationID: destination.id
            ),
            prompt: "Implement the approved template.", startsImmediately: false
        )

        let transaction = try XCTUnwrap(test.model.prepareChatHandoff(request))
        XCTAssertEqual(transaction.destination.id, destination.id)
        XCTAssertNil(transaction.destination.isUnread)
        XCTAssertEqual(transaction.destination.messages.first, destination.messages.first)
        XCTAssertEqual(transaction.destination.messages.count, 2)
        test.model.restorePreparedChatHandoff(transaction)
        XCTAssertEqual(test.model.conversations.first { $0.id == destination.id }?.messages, destination.messages)
        XCTAssertEqual(test.model.conversations.first { $0.id == destination.id }?.updatedAt, destination.updatedAt)
        XCTAssertEqual(test.model.conversations.first { $0.id == destination.id }?.isUnread, true)
    }

    func testCancelledHandoffRestoresSourceAndExactDraft() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = sourceChat(test)
        let project = try addProject("Destination", to: test)
        test.model.composer.draft = "  Transfer the approved work.\n"
        let request = VyronChatHandoffRequest(
            source: VyronChatHandoffPresentation(sourceID: source.id, initialRequest: test.model.composer.draft),
            destination: VyronChatHandoffSelection(projectPath: project.path, workspacePath: project.path),
            prompt: "Implement the approved template.", startsImmediately: false
        )
        let task = Task { @MainActor in await test.model.handOffChat(request) }
        task.cancel()
        let completed = await task.value

        XCTAssertFalse(completed)
        XCTAssertEqual(test.model.selectedConversationID, source.id)
        XCTAssertEqual(test.model.composer.draft, "  Transfer the approved work.\n")
        XCTAssertEqual(test.model.conversations.map(\.id), [source.id])
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
    }

    func testCancellationAfterActivationRestoresUnselectedComposerWorkspaceAndMode() async throws {
        for hasWorkspace in [false, true] {
            let test = VyronQueueTestHarness()
            defer { test.cleanUp() }
            let source = sourceChat(test)
            let destination = try addProject("Destination", to: test)
            let original = hasWorkspace ? try addProject("Original", to: test) : nil
            test.model.newConversation()
            if let original { await test.model.loadWorkspace(original, projectPath: original.path) }
            let originalMode: ComposerMode = hasWorkspace ? .plan : .chat
            test.model.composer.mode = originalMode
            let originalProjectPath = test.model.workspaceState.selectedProjectPath
            var handoff: Task<Bool, Never>?
            let selection = test.model.$selectedConversationID.sink { id in
                if id != nil { handoff?.cancel() }
            }
            let request = request(source: source, project: destination)
            handoff = Task { @MainActor in await test.model.handOffChat(request) }
            let completed = await handoff?.value
            withExtendedLifetime(selection) {}

            XCTAssertEqual(completed, false)
            XCTAssertNil(test.model.selectedConversationID)
            XCTAssertEqual(test.model.workspaceState.workspaceURL, original)
            XCTAssertEqual(test.model.workspaceState.selectedProjectPath, originalProjectPath)
            XCTAssertEqual(test.model.composer.mode, originalMode)
            XCTAssertTrue(test.model.composer.draft.isEmpty)
            XCTAssertEqual(test.model.conversations.map(\.id), [source.id])
            XCTAssertEqual(test.model.chatSchedulingWorkspaceMatches, hasWorkspace)
        }
    }

    private func sourceChat(_ test: VyronQueueTestHarness) -> Conversation {
        var source = Conversation(title: "Source", workspacePath: nil)
        source.mode = ComposerMode.chat.rawValue
        source.messages = [
            ChatMessage(role: "user", content: "Original source request"),
            ChatMessage(role: "assistant", content: "Original answer")
        ]
        test.model.conversations = [source]
        test.model.selectedConversationID = source.id
        test.model.registerSidebarConversation(source.id)
        return source
    }

    private func addProject(_ name: String, to test: VyronQueueTestHarness) throws -> URL {
        let project = test.directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        XCTAssertTrue(test.model.changeSidebar {
            try $0.updateProject(path: project.path, name: name, sourceFolders: [project.path])
        })
        return project
    }

    private func request(source: Conversation, project: URL) -> VyronChatHandoffRequest {
        VyronChatHandoffRequest(
            source: VyronChatHandoffPresentation(sourceID: source.id),
            destination: VyronChatHandoffSelection(projectPath: project.path, workspacePath: project.path),
            prompt: "Implement the approved template in this destination.",
            startsImmediately: false
        )
    }
}
