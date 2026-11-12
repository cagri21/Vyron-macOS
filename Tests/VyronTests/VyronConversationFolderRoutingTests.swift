import Foundation
import VyronCore
import XCTest
@testable import Vyron

@MainActor
final class VyronConversationFolderRoutingTests: XCTestCase {
    func testConfirmingAMoveUpdatesTheSameConversation() async throws {
        try await exerciseMove(approved: true)
    }

    func testCancelingAMoveKeepsTheConversationInItsCurrentFolder() async throws {
        try await exerciseMove(approved: false)
    }

    private func exerciseMove(approved: Bool) async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let original = test.project.resolvingSymlinksInPath()
        let destinationProject = test.directory.resolvingSymlinksInPath()
            .appendingPathComponent("Study", isDirectory: true)
        let destination = destinationProject.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let provider = VyronConversationMoveTestProvider(destinationPath: destination.path)
        test.select(test.profile(), provider: provider, capabilities: ["tools"])
        test.model.skillContextLoader = { _ in .empty }
        await test.model.loadWorkspace(original)
        test.model.composer.mode = .agent
        XCTAssertTrue(test.model.changeSidebar {
            try $0.updateProject(path: destinationProject.path, name: "Study Notes", sourceFolders: [destination.path])
        })
        var conversation = Conversation(title: "Work in progress", workspacePath: original.path)
        conversation.projectPath = original.path
        conversation.mode = ComposerMode.agent.rawValue
        let existingMessage = ChatMessage(role: "user", content: "Keep this context.")
        conversation.messages = [existingMessage]
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id
        test.model.registerSidebarConversation(conversation.id)

        let prompt = "Move this conversation to Study Notes."
        test.model.composer.draft = prompt
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { test.model.interactions.pendingCommandApproval != nil || !test.model.foregroundRun.isGenerating }

        let review = try XCTUnwrap(test.model.interactions.pendingCommandApproval)
        XCTAssertEqual(review.action, .moveConversation)
        XCTAssertEqual(review.command, destination.path)
        XCTAssertNil(test.model.handoff.chatHandoffPresentation)
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, original.path)
        XCTAssertEqual(test.model.selectedConversationID, conversation.id)
        let receivedContext = await provider.receivedDestinationContext
        XCTAssertTrue(receivedContext)

        test.model.respondToCommandApproval(approved, approvalID: review.id)
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let expectedPath = approved ? destination.path : original.path
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, expectedPath)
        XCTAssertEqual(
            test.model.workspaceState.selectedProjectPath,
            approved ? destinationProject.path : original.path
        )
        XCTAssertEqual(test.model.conversations.map(\.id), [conversation.id])
        XCTAssertEqual(test.model.selectedConversationID, conversation.id)
        XCTAssertEqual(test.model.selectedConversation?.workspacePath, expectedPath)
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.contains(.project(destination.path)))
        XCTAssertEqual(test.model.messages.first?.id, existingMessage.id)
        XCTAssertTrue(test.model.messages.contains { $0.role == "user" && $0.content == prompt })
        XCTAssertNil(test.model.interactions.pendingCommandApproval)
    }
}
