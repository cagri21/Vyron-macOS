import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatHandoffToolTests: XCTestCase {
    func testProjectCatalogContainsOnlySavedMetadataWithOpaqueIDs() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        var unsaved = Conversation(title: "Private unsaved project", workspacePath: "/Unsaved/private")
        unsaved.messages = [ChatMessage(role: "user", content: "PRIVATE_BODY")]
        test.model.conversations.append(unsaved)

        let result = try test.model.executeChatHandoffTool(
            DevelopmentToolCall(name: VyronChatHandoffTools.list, arguments: [:]), context: context
        )
        let projects = try JSONDecoder().decode([[String: String]].self, from: Data(result.text.utf8))
        XCTAssertFalse(result.isError)
        XCTAssertEqual(projects.count, 2)
        XCTAssertTrue(projects.allSatisfy { Set($0.keys) == Set(["project_id", "name"]) })
        XCTAssertTrue(projects.allSatisfy { $0["project_id"]?.hasPrefix("project-") == true })
        XCTAssertFalse(result.text.contains("/Saved/"))
        XCTAssertFalse(result.text.contains("/Unsaved/"))
        XCTAssertFalse(result.text.contains("PRIVATE_BODY"))
        XCTAssertNil(test.model.handoff.pendingNativeChatHandoff)
    }

    func testChatCatalogFiltersArchivedChatOnlyQueuedAndForeignWorkspaceEntries() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        let project = try destination(in: context)
        var available = Conversation(title: "Available Work", workspacePath: project.path)
        available.mode = ComposerMode.agent.rawValue
        available.messages = [ChatMessage(role: "user", content: "PRIVATE_DESTINATION_BODY")]
        var chatOnly = Conversation(title: "Chat only", workspacePath: project.path)
        chatOnly.mode = ComposerMode.chat.rawValue
        var archived = Conversation(title: "Archived", workspacePath: project.path)
        archived.mode = ComposerMode.agent.rawValue
        var queued = Conversation(title: "Queued", workspacePath: project.path)
        queued.queuedMessages = [VyronQueuedMessage(content: "Unsent guidance")]
        var foreign = Conversation(title: "Other source", workspacePath: "/Outside/source")
        foreign.projectPath = project.path
        for chat in [available, chatOnly, archived, queued, foreign] {
            test.model.conversations.append(chat)
            test.model.registerSidebarConversation(chat.id)
        }
        XCTAssertTrue(test.model.changeSidebar { try $0.archiveConversations(ids: [archived.id]) })
        let result = try test.model.executeChatHandoffTool(
            DevelopmentToolCall(name: VyronChatHandoffTools.list, arguments: ["project_id": .string(project.id)]),
            context: context
        )
        let chats = try JSONDecoder().decode([[String: String]].self, from: Data(result.text.utf8))
        XCTAssertFalse(result.isError)
        XCTAssertEqual(chats, [["conversation_id": available.id.uuidString, "title": available.title]])
        XCTAssertFalse(result.text.contains("PRIVATE_DESTINATION_BODY"))
        XCTAssertFalse(result.text.contains(project.path))
    }

    func testPrepareRejectsArbitraryPathsUnknownProjectsAndUnknownChatIDs() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        for value in ["/Saved/destination", "/Outside/arbitrary", "project-999"] {
            let result = try test.model.executeChatHandoffTool(
                DevelopmentToolCall(name: VyronChatHandoffTools.prepare, arguments: [
                    "project_id": .string(value), "request": .string("Implement the settings")
                ]), context: context
            )
            XCTAssertTrue(result.isError)
            XCTAssertNil(test.model.handoff.pendingNativeChatHandoff)
        }
        let project = try destination(in: context)
        let invalidChat = try test.model.executeChatHandoffTool(
            DevelopmentToolCall(name: VyronChatHandoffTools.prepare, arguments: [
                "project_id": .string(project.id), "conversation_id": .string(UUID().uuidString),
                "request": .string("Implement the settings")
            ]), context: context
        )
        XCTAssertTrue(invalidChat.isError)
        let arbitraryPath = try test.model.executeChatHandoffTool(
            DevelopmentToolCall(name: VyronChatHandoffTools.prepare, arguments: [
                "project_id": .string(project.id), "workspace_path": .string("/Outside/arbitrary"),
                "request": .string("Implement the settings")
            ]), context: context
        )
        XCTAssertTrue(arbitraryPath.isError)
        XCTAssertNil(test.model.handoff.pendingNativeChatHandoff)
    }

    func testStaleResponseOrProjectSnapshotCannotPrepareHandoff() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        let project = try destination(in: context)
        let call = prepare(project.id)
        test.model.foregroundRun.stop()
        test.model.beginTestForegroundResponse()
        XCTAssertThrowsError(try test.model.executeChatHandoffTool(call, context: context)) {
            XCTAssertTrue($0 is CancellationError)
        }
        test.model.foregroundRun.stop()
        test.model.foregroundRun.begin(context.response)
        test.model.selectedConversationID = UUID()
        XCTAssertThrowsError(try test.model.executeChatHandoffTool(call, context: context)) {
            XCTAssertTrue($0 is CancellationError)
        }
        test.model.selectedConversationID = context.response.conversationID
        XCTAssertTrue(test.model.changeSidebar {
            try $0.updateProject(path: project.path, name: "Changed", sourceFolders: ["/Saved/new-source"])
        })
        XCTAssertTrue(try test.model.executeChatHandoffTool(call, context: context).isError)
        XCTAssertNil(test.model.handoff.pendingNativeChatHandoff)
    }

    func testPreparationWaitsForSourceCompletionWithoutNavigatingSavingOrSending() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        let project = try destination(in: context)
        XCTAssertTrue(test.model.saveHistory())
        let historyURL = test.directory.appendingPathComponent("conversations.json")
        let previousHistory = try Data(contentsOf: historyURL)
        let previousWorkspace = test.model.workspaceState.workspaceURL
        let result = try test.model.executeChatHandoffTool(prepare(project.id), context: context)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(test.model.selectedConversationID, context.response.conversationID)
        XCTAssertEqual(test.model.workspaceState.workspaceURL, previousWorkspace)
        XCTAssertNil(test.model.handoff.chatHandoffPresentation)
        XCTAssertEqual(test.model.handoff.pendingNativeChatHandoff?.presentation.destination?.projectPath, project.path)
        XCTAssertEqual(try Data(contentsOf: historyURL), previousHistory)
        XCTAssertEqual(test.model.conversations.count, 1)
        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)

        test.model.foregroundRun.complete(context.response.generationID)
        XCTAssertTrue(test.model.presentPendingChatHandoff(generationID: context.response.generationID, completed: true))
        XCTAssertEqual(test.model.handoff.chatHandoffPresentation?.sourceID, context.response.conversationID)
        XCTAssertEqual(test.model.selectedConversationID, context.response.conversationID)
        XCTAssertNil(test.model.handoff.pendingNativeChatHandoff)
    }

    func testCanceledResponseDiscardsPendingProposal() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        let project = try destination(in: context)
        XCTAssertFalse(try test.model.executeChatHandoffTool(prepare(project.id), context: context).isError)
        test.model.stopGeneration()
        XCTAssertNil(test.model.handoff.pendingNativeChatHandoff)
        XCTAssertNil(test.model.handoff.chatHandoffPresentation)
        XCTAssertFalse(test.model.presentPendingChatHandoff(generationID: context.response.generationID, completed: true))
    }

    func testFailedResponseDoesNotPresentProposalAndWrongGenerationDoesNotConsumeIt() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        let project = try destination(in: context)
        XCTAssertFalse(try test.model.executeChatHandoffTool(prepare(project.id), context: context).isError)
        XCTAssertFalse(test.model.presentPendingChatHandoff(generationID: UUID(), completed: true))
        XCTAssertNotNil(test.model.handoff.pendingNativeChatHandoff)
        XCTAssertNil(test.model.handoff.chatHandoffPresentation)
        XCTAssertFalse(test.model.presentPendingChatHandoff(generationID: context.response.generationID, completed: false))
        XCTAssertNil(test.model.handoff.pendingNativeChatHandoff)
        XCTAssertNil(test.model.handoff.chatHandoffPresentation)
    }

    private func startResponse(_ test: VyronQueueTestHarness) -> VyronChatHandoffToolContext {
        test.model.sidebarState.sidebarOrganization = SidebarOrganization()
        var source = Conversation(title: "Source", workspacePath: "/Saved/source")
        source.mode = ComposerMode.agent.rawValue
        source.messages = [
            ChatMessage(role: "user", content: "Continue the task in the destination project"),
            ChatMessage(role: "assistant", content: "Preparing a handoff")
        ]
        test.model.conversations = [source]
        test.model.selectedConversationID = source.id
        test.model.registerSidebarConversation(source.id)
        test.model.registerSidebarProject("/Saved/destination")
        let response = VyronResponseIdentity(
            generationID: UUID(), conversationID: source.id, messageID: source.messages[1].id
        )
        test.model.foregroundRun.begin(response)
        return test.model.chatHandoffToolContext(response: response)
    }

    private func destination(in context: VyronChatHandoffToolContext) throws -> VyronChatHandoffToolProject {
        try XCTUnwrap(context.projects.first { $0.path == "/Saved/destination" })
    }

    private func prepare(_ projectID: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: VyronChatHandoffTools.prepare, arguments: [
            "project_id": .string(projectID), "request": .string("Implement the settings")
        ])
    }
}
