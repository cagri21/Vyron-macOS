import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore
import VyronDevelopment

@MainActor
final class VyronCreatedProjectTests: XCTestCase {
    func testActiveTaskAdoptsCreatedProjectWithoutReplacingConversationOrGeneration() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        let original = try folder("Original", in: test.directory)
        let created = try folder("Desktop/Finator", in: test.directory)
        try Data("Original project\n".utf8).write(to: original.appendingPathComponent("README.md"))
        await test.model.loadWorkspace(original)
        let generation = UUID()
        let conversation = prepare(test.model, project: original, generationID: generation)
        let development = try DevelopmentWorkspace(rootURL: created)
        _ = try await development.writeFile(path: "README.md", content: "# Finator\n")

        try await test.model.adoptCreatedProject(
            development, generationID: generation, conversationID: conversation.id
        )

        XCTAssertEqual(test.model.workspaceState.workspaceURL, created)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, created.path)
        XCTAssertEqual(test.model.selectedConversationID, conversation.id)
        XCTAssertEqual(test.model.conversations.map(\.id), [conversation.id])
        XCTAssertEqual(test.model.conversations.first?.messages, conversation.messages)
        XCTAssertEqual(test.model.conversations.first?.workspacePath, created.path)
        XCTAssertEqual(test.model.conversations.first?.projectPath, created.path)
        XCTAssertEqual(test.model.foregroundRun.activeGeneration, generation)
        XCTAssertEqual(test.model.foregroundRun.activeResponse?.conversationID, conversation.id)
        XCTAssertEqual(test.model.foregroundRun.activeResponse?.messageID, conversation.messages.last?.id)
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        XCTAssertTrue(test.model.foregroundRun.isDeveloping)
        XCTAssertTrue(test.model.workspaceState.developmentWorkspaces[created.path] === development)
        XCTAssertEqual(test.model.workspaceState.workspaceFiles.map(\.path), ["README.md"])
        XCTAssertEqual(test.model.inspector.developmentFiles.map(\.path), ["README.md"])
        XCTAssertEqual(test.model.inspector.developmentChanges.map(\.path), ["README.md"])
        XCTAssertEqual(test.model.sidebarProjectSourceFolders(created.path), [created.path])
        XCTAssertTrue(test.model.sidebarState.sidebarOrganization.contains(.project(created.path)))
        XCTAssertEqual(test.model.sidebarProjectConversations(created.path).map(\.id), [conversation.id])
        XCTAssertEqual(test.model.workspaceState.recentWorkspacePaths.first, created.path)
        XCTAssertEqual(test.model.workspaceState.recentWorkspacePaths.filter { $0 == created.path }.count, 1)
        XCTAssertEqual(UserDefaults.standard.string(forKey: VyronUserDefaultsKey.workspacePath.rawValue), created.path)
        XCTAssertEqual(
            UserDefaults.standard.stringArray(forKey: VyronUserDefaultsKey.recentWorkspacePaths.rawValue),
            test.model.workspaceState.recentWorkspacePaths
        )
        XCTAssertEqual(
            try String(contentsOf: original.appendingPathComponent("README.md"), encoding: .utf8),
            "Original project\n"
        )
    }

    func testCreatedProjectAssociationPersistsAndConversationReopensAtNewFolder() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        let original = try folder("Original", in: test.directory)
        let created = try folder("Finator", in: test.directory)
        await test.model.loadWorkspace(original)
        let generation = UUID()
        let conversation = prepare(test.model, project: original, generationID: generation)
        let development = try DevelopmentWorkspace(rootURL: created)

        try await test.model.adoptCreatedProject(
            development, generationID: generation, conversationID: conversation.id
        )
        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.scheduledTasks.shutdown() }
        let restored = try XCTUnwrap(reopened.conversations.first { $0.id == conversation.id })

        XCTAssertEqual(restored.messages, conversation.messages)
        XCTAssertEqual(restored.workspacePath, created.path)
        XCTAssertEqual(restored.projectPath, created.path)
        XCTAssertEqual(reopened.workspaceState.workspaceURL, created)
        XCTAssertEqual(reopened.workspaceState.selectedProjectPath, created.path)
        XCTAssertEqual(reopened.sidebarProjectSourceFolders(created.path), [created.path])
        let activated = await reopened.activateChatHandoff(conversation.id)
        XCTAssertTrue(activated)
        XCTAssertEqual(reopened.selectedConversationID, conversation.id)
        XCTAssertEqual(reopened.workspaceState.workspaceURL, created)
        XCTAssertNotNil(reopened.workspaceState.developmentWorkspaces[created.path])
    }

    func testStaleGenerationCannotAdoptCreatedProject() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        let original = try folder("Original", in: test.directory)
        let created = try folder("Finator", in: test.directory)
        await test.model.loadWorkspace(original)
        let generation = UUID()
        let conversation = prepare(test.model, project: original, generationID: generation)
        let development = try DevelopmentWorkspace(rootURL: created)
        let organization = test.model.sidebarState.sidebarOrganization
        let recent = test.model.workspaceState.recentWorkspacePaths
        XCTAssertTrue(test.model.saveHistory())
        let history = try persistedHistory(in: test.directory)

        do {
            try await test.model.adoptCreatedProject(
                development, generationID: UUID(), conversationID: conversation.id
            )
            XCTFail("A stale generation must not adopt another project.")
        } catch is CancellationError {}

        assertOriginalContext(test.model, conversation: conversation, project: original, generationID: generation)
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(test.model.workspaceState.recentWorkspacePaths, recent)
        XCTAssertNil(test.model.workspaceState.developmentWorkspaces[created.path])
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testAdoptionAddsRootToExistingProjectWithoutLosingItsNameOrSourceFolders() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        let original = try folder("Original", in: test.directory)
        let created = try folder("Finator", in: test.directory)
        let existingSource = try folder("SharedSource", in: test.directory)
        await test.model.loadWorkspace(original)
        var organization = test.model.sidebarState.sidebarOrganization
        try organization.updateProject(
            path: created.path, name: "Finator Product", sourceFolders: [existingSource.path]
        )
        try test.model.sidebarState.sidebarStore.save(organization)
        test.model.sidebarState.sidebarOrganization = organization
        let generation = UUID()
        let conversation = prepare(test.model, project: original, generationID: generation)
        let development = try DevelopmentWorkspace(rootURL: created)

        try await test.model.adoptCreatedProject(
            development, generationID: generation, conversationID: conversation.id
        )

        XCTAssertEqual(test.model.sidebarProjectName(created.path), "Finator Product")
        XCTAssertEqual(test.model.sidebarProjectSourceFolders(created.path), [existingSource.path, created.path])
        XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), test.model.sidebarState.sidebarOrganization)
        XCTAssertEqual(test.model.conversations.first?.workspacePath, created.path)
        XCTAssertEqual(test.model.conversations.first?.messages, conversation.messages)
        XCTAssertEqual(test.model.foregroundRun.activeGeneration, generation)
        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.scheduledTasks.shutdown() }
        XCTAssertEqual(reopened.sidebarProjectName(created.path), "Finator Product")
        XCTAssertEqual(reopened.sidebarProjectSourceFolders(created.path), [existingSource.path, created.path])
        let activated = await reopened.activateChatHandoff(conversation.id)
        XCTAssertTrue(activated)
        XCTAssertEqual(reopened.workspaceState.workspaceURL, created)
        XCTAssertEqual(reopened.workspaceState.selectedProjectPath, created.path)
    }

    func testAnotherSelectedConversationPreventsProjectAdoption() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        let original = try folder("Original", in: test.directory)
        let created = try folder("Finator", in: test.directory)
        await test.model.loadWorkspace(original)
        let generation = UUID()
        let conversation = prepare(test.model, project: original, generationID: generation)
        let other = Conversation(title: "Other conversation", workspacePath: original.path)
        test.model.conversations.append(other)
        test.model.selectedConversationID = other.id
        let development = try DevelopmentWorkspace(rootURL: created)
        let organization = test.model.sidebarState.sidebarOrganization
        XCTAssertTrue(test.model.saveHistory())
        let history = try persistedHistory(in: test.directory)

        do {
            try await test.model.adoptCreatedProject(
                development, generationID: generation, conversationID: conversation.id
            )
            XCTFail("Project adoption must belong to the selected conversation.")
        } catch is CancellationError {}

        XCTAssertEqual(test.model.selectedConversationID, other.id)
        XCTAssertEqual(test.model.workspaceState.workspaceURL, original)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, original.path)
        XCTAssertEqual(test.model.conversations.first?.workspacePath, original.path)
        XCTAssertEqual(test.model.conversations.first?.messages, conversation.messages)
        XCTAssertEqual(test.model.foregroundRun.activeGeneration, generation)
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertNil(test.model.workspaceState.developmentWorkspaces[created.path])
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testCancelledTaskLeavesProjectAndConversationUnchanged() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        let original = try folder("Original", in: test.directory)
        let created = try folder("Finator", in: test.directory)
        await test.model.loadWorkspace(original)
        let generation = UUID()
        let conversation = prepare(test.model, project: original, generationID: generation)
        let development = try DevelopmentWorkspace(rootURL: created)
        let organization = test.model.sidebarState.sidebarOrganization
        let recent = test.model.workspaceState.recentWorkspacePaths
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await test.model.adoptCreatedProject(
                development, generationID: generation, conversationID: conversation.id
            )
        }

        do {
            try await task.value
            XCTFail("A canceled task must not adopt another project.")
        } catch is CancellationError {}

        assertOriginalContext(test.model, conversation: conversation, project: original, generationID: generation)
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(test.model.workspaceState.recentWorkspacePaths, recent)
        XCTAssertNil(test.model.workspaceState.developmentWorkspaces[created.path])
    }

    func testHistoryWriteFailureDoesNotAdoptCreatedProjectOrMoveConversation() async throws {
        let test = VyronQueueTestHarness()
        defer { cleanUp(test) }
        let original = try folder("Original", in: test.directory)
        let created = try folder("Finator", in: test.directory)
        await test.model.loadWorkspace(original)
        let generation = UUID()
        let conversation = prepare(test.model, project: original, generationID: generation)
        let development = try DevelopmentWorkspace(rootURL: created)
        let recent = test.model.workspaceState.recentWorkspacePaths
        let organization = test.model.sidebarState.sidebarOrganization
        XCTAssertTrue(test.model.saveHistory())
        let history = try persistedHistory(in: test.directory)
        let historyURL = test.directory.appendingPathComponent("conversations.json")
        let retainedHistory = test.directory.appendingPathComponent("retained-conversations.json")
        try FileManager.default.moveItem(at: historyURL, to: retainedHistory)
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)

        do {
            try await test.model.adoptCreatedProject(
                development, generationID: generation, conversationID: conversation.id
            )
            XCTFail("A project move must fail when its conversation association cannot be saved.")
        } catch is CancellationError {
            XCTFail("The active task was not canceled; persisting the conversation association failed.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        assertOriginalContext(test.model, conversation: conversation, project: original, generationID: generation)
        XCTAssertEqual(test.model.workspaceState.recentWorkspacePaths, recent)
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), organization)
        XCTAssertNil(test.model.workspaceState.developmentWorkspaces[created.path])
        XCTAssertEqual(UserDefaults.standard.string(forKey: VyronUserDefaultsKey.workspacePath.rawValue), original.path)
        XCTAssertEqual(try Data(contentsOf: retainedHistory), history)
        XCTAssertEqual(try historyURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: historyURL.path).isEmpty)
        XCTAssertNotNil(test.model.errorMessage)
    }

    private func prepare(_ model: AppModel, project: URL, generationID: UUID) -> Conversation {
        var conversation = Conversation(title: "Create Finator", workspacePath: project.path)
        conversation.projectPath = project.path
        conversation.messages = [
            ChatMessage(role: "user", content: "Create Finator on the Desktop."),
            ChatMessage(role: "assistant", content: "Creating the project folder.")
        ]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        let response = model.beginTestForegroundResponse(generationID: generationID)
        model.foregroundRun.beginDevelopment(response)
        return conversation
    }

    private func assertOriginalContext(
        _ model: AppModel,
        conversation: Conversation,
        project: URL,
        generationID: UUID
    ) {
        XCTAssertEqual(model.workspaceState.workspaceURL, project)
        XCTAssertEqual(model.workspaceState.selectedProjectPath, project.path)
        XCTAssertEqual(model.selectedConversationID, conversation.id)
        XCTAssertEqual(model.conversations.first?.id, conversation.id)
        XCTAssertEqual(model.conversations.first?.messages, conversation.messages)
        XCTAssertEqual(model.conversations.first?.workspacePath, project.path)
        XCTAssertEqual(model.conversations.first?.projectPath, project.path)
        XCTAssertEqual(model.foregroundRun.activeGeneration, generationID)
        XCTAssertTrue(model.foregroundRun.isGenerating)
        XCTAssertTrue(model.foregroundRun.isDeveloping)
    }

    private func folder(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func persistedHistory(in directory: URL) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("conversations.json"))
    }

    private func cleanUp(_ test: VyronQueueTestHarness) {
        // These tests own a synthetic generation, without a generation task to cancel or settle.
        test.model.foregroundRun.stop()
        test.cleanUp()
    }
}
