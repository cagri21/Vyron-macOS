import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronSidebarProjectActionsTests: XCTestCase {
    func testProjectNamePersistsWithoutChangingHistoryOrWorkspacePaths() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let path = test.directory.appendingPathComponent("ActualProject").path
        let chat = conversation(title: "Existing task", path: path)
        try prepare(test.model, conversations: [chat], projectPaths: [path])
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: path, isDirectory: true)
        test.model.selectedConversationID = chat.id
        let history = try persistedHistory(in: test.directory)

        XCTAssertTrue(test.model.renameSidebarProject(path, name: "  Friendly Project  "))

        XCTAssertEqual(test.model.sidebarProjectName(path), "Friendly Project")
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, path)
        XCTAssertEqual(test.model.conversations.first?.workspacePath, path)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.scheduledTasks.shutdown() }
        XCTAssertEqual(reopened.sidebarProjectName(path), "Friendly Project")
        XCTAssertEqual(reopened.sidebarState.sidebarOrganization.allProjects, [path])
        XCTAssertEqual(reopened.conversations.first?.workspacePath, path)
        XCTAssertEqual(reopened.conversations.first?.messages, chat.messages)
    }

    func testBulkArchiveIncludesPinnedAndMovedChatsButPreservesOtherProjectsAndHistory() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project").path
        let otherProject = test.directory.appendingPathComponent("OtherProject").path
        let normal = conversation(title: "Normal", path: project)
        let pinned = conversation(title: "Pinned", path: project)
        let moved = conversation(title: "Moved", path: project)
        let other = conversation(title: "Other", path: otherProject)
        let chats = [normal, pinned, moved, other]
        try prepare(test.model, conversations: chats, projectPaths: [project, otherProject])
        let folderID = try XCTUnwrap(test.model.createSidebarFolder(name: "Custom section"))
        XCTAssertTrue(test.model.moveSidebarItem(.conversation(moved.id), toFolder: folderID))
        test.model.toggleSidebarPin(.conversation(pinned.id))
        test.model.selectedConversationID = other.id
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: otherProject, isDirectory: true)
        test.model.composer.draft = "Keep my other project's draft."
        let history = try persistedHistory(in: test.directory)

        XCTAssertTrue(test.model.archiveSidebarProject(project))

        XCTAssertEqual(
            test.model.sidebarState.sidebarOrganization.archivedConversationIDs,
            [normal.id, pinned.id, moved.id]
        )
        XCTAssertEqual(Set(test.model.archivedSidebarConversations.map(\.id)), [normal.id, pinned.id, moved.id])
        XCTAssertTrue(test.model.sidebarProjectChats(project).isEmpty)
        XCTAssertTrue(test.model.sidebarChats(in: folderID).isEmpty)
        XCTAssertNil(test.model.sidebarConversation(pinned.id))
        XCTAssertEqual(test.model.sidebarProjectChats(otherProject).map(\.id), [other.id])
        XCTAssertEqual(test.model.conversations.map(\.id), chats.map(\.id))
        XCTAssertEqual(test.model.selectedConversationID, other.id)
        XCTAssertEqual(test.model.composer.draft, "Keep my other project's draft.")
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testActiveProjectRejectsArchiveAndRemovalWithoutLosingDraftOrHistory() throws {
        let test = VyronQueueTestHarness()
        defer {
            test.model.foregroundRun.stop()
            test.cleanUp()
        }
        let project = test.directory.appendingPathComponent("Project").path
        let chat = conversation(title: "Active task", path: project)
        try prepare(test.model, conversations: [chat], projectPaths: [project])
        test.model.selectedConversationID = chat.id
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: project, isDirectory: true)
        test.model.composer.draft = "Unsent follow-up"
        test.model.beginTestForegroundResponse()
        let organization = test.model.sidebarState.sidebarOrganization
        let history = try persistedHistory(in: test.directory)

        XCTAssertFalse(test.model.canArchiveSidebarProject(project))
        XCTAssertFalse(test.model.canRemoveSidebarProject(project))
        XCTAssertFalse(test.model.archiveSidebarProject(project))
        XCTAssertFalse(test.model.removeSidebarProject(project))

        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(test.model.selectedConversationID, chat.id)
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, project)
        XCTAssertEqual(test.model.composer.draft, "Unsent follow-up")
        XCTAssertEqual(test.model.workspaceState.recentWorkspacePaths, [project])
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testRestorePreservesPinAndSectionAndReopensProjectAndAncestors() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project").path
        let chat = conversation(title: "Archived task", path: project)
        try prepare(test.model, conversations: [chat], projectPaths: [project])
        let parentID = try XCTUnwrap(test.model.createSidebarFolder(name: "Parent"))
        let childID = try XCTUnwrap(test.model.createSidebarFolder(name: "Child", parentID: parentID))
        XCTAssertTrue(test.model.moveSidebarItem(.project(project), toFolder: childID))
        XCTAssertTrue(test.model.moveSidebarItem(.conversation(chat.id), toFolder: childID))
        test.model.toggleSidebarPin(.conversation(chat.id))
        XCTAssertTrue(test.model.archiveSidebarProject(project))
        test.model.setSidebarProjectExpanded(project, expanded: false)
        test.model.setSidebarFolderExpanded(childID, expanded: false)
        test.model.setSidebarFolderExpanded(parentID, expanded: false)

        XCTAssertTrue(test.model.restoreSidebarConversation(chat.id))

        let organization = test.model.sidebarState.sidebarOrganization
        XCTAssertFalse(organization.isConversationArchived(chat.id))
        XCTAssertTrue(organization.isPinned(.conversation(chat.id)))
        XCTAssertEqual(organization.folderID(for: .conversation(chat.id)), childID)
        XCTAssertEqual(organization.folderID(for: .project(project)), childID)
        XCTAssertTrue(organization.isProjectExpanded(project))
        XCTAssertTrue(organization.isFolderExpanded(childID))
        XCTAssertTrue(organization.isFolderExpanded(parentID))
        XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), organization)
        XCTAssertEqual(test.model.sidebarConversation(chat.id)?.messages, chat.messages)
    }

    func testRemovingProjectPreservesFilesAndHistoryAndStaysRemovedAfterReopening() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let projectURL = test.directory.appendingPathComponent("ActualProject", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let sourceURL = projectURL.appendingPathComponent("Keep.swift")
        let source = Data("let keep = true\n".utf8)
        try source.write(to: sourceURL)
        let otherProject = test.directory.appendingPathComponent("OtherProject").path
        let chat = conversation(title: "Preserved task", path: projectURL.path)
        try prepare(test.model, conversations: [chat], projectPaths: [projectURL.path, otherProject])
        XCTAssertTrue(test.model.renameSidebarProject(projectURL.path, name: "Friendly Project"))
        test.model.toggleSidebarPin(.project(projectURL.path))
        test.model.workspaceState.workspaceURL = projectURL
        test.model.selectedConversationID = chat.id
        UserDefaults.standard.set(projectURL.path, forKey: VyronUserDefaultsKey.workspacePath.rawValue)
        let history = try persistedHistory(in: test.directory)

        XCTAssertTrue(test.model.removeSidebarProject(projectURL.path))

        XCTAssertEqual(try Data(contentsOf: sourceURL), source)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
        XCTAssertEqual(test.model.conversations.map(\.id), [chat.id])
        XCTAssertEqual(test.model.sidebarChats(in: nil).map(\.id), [chat.id])
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.contains(.project(projectURL.path)))
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.isPinned(.project(projectURL.path)))
        XCTAssertEqual(test.model.workspaceState.recentWorkspacePaths, [otherProject])
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: VyronUserDefaultsKey.recentWorkspacePaths.rawValue), [otherProject])
        XCTAssertNil(test.model.workspaceState.workspaceURL)
        XCTAssertNil(test.model.selectedConversationID)
        XCTAssertNil(UserDefaults.standard.object(forKey: VyronUserDefaultsKey.workspacePath.rawValue))
        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.scheduledTasks.shutdown() }
        XCTAssertFalse(reopened.sidebarState.sidebarOrganization.contains(.project(projectURL.path)))
        XCTAssertEqual(reopened.sidebarState.sidebarOrganization.allProjects, [otherProject])
        XCTAssertEqual(reopened.conversations.map(\.id), [chat.id])
        XCTAssertEqual(reopened.sidebarChats(in: nil).map(\.id), [chat.id])
        XCTAssertNil(reopened.workspaceState.workspaceURL)
    }

    func testCorruptSidebarRollsBackProjectMutationsAndPreservesCurrentContext() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project").path
        let chat = conversation(title: "Preserved task", path: project)
        try prepare(test.model, conversations: [chat], projectPaths: [project])
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: project, isDirectory: true)
        test.model.selectedConversationID = chat.id
        test.model.composer.draft = "Keep this draft."
        let organization = test.model.sidebarState.sidebarOrganization
        let history = try persistedHistory(in: test.directory)
        let corrupt = Data("{ truncated sidebar".utf8)
        try corrupt.write(to: test.model.sidebarState.sidebarStore.fileURL)

        XCTAssertFalse(test.model.renameSidebarProject(project, name: "Cannot save"))
        XCTAssertFalse(test.model.archiveSidebarProject(project))
        XCTAssertFalse(test.model.removeSidebarProject(project))

        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(try Data(contentsOf: test.model.sidebarState.sidebarStore.fileURL), corrupt)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
        XCTAssertEqual(test.model.selectedConversationID, chat.id)
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, project)
        XCTAssertEqual(test.model.composer.draft, "Keep this draft.")
        XCTAssertEqual(test.model.workspaceState.recentWorkspacePaths, [project])
        XCTAssertNotNil(test.model.errorMessage)
    }

    private func prepare(_ model: AppModel, conversations: [Conversation], projectPaths: [String]) throws {
        UserDefaults.standard.removeObject(forKey: VyronUserDefaultsKey.workspacePath.rawValue)
        UserDefaults.standard.set(projectPaths, forKey: VyronUserDefaultsKey.recentWorkspacePaths.rawValue)
        model.workspaceState.recentWorkspacePaths = projectPaths
        model.workspaceState.workspaceURL = nil
        model.conversations = conversations
        var organization = SidebarOrganization()
        for path in projectPaths { try organization.registerProject(path: path) }
        for conversation in conversations { organization.registerConversation(id: conversation.id) }
        try model.sidebarState.sidebarStore.save(organization)
        model.sidebarState.sidebarOrganization = organization
        XCTAssertTrue(model.saveHistory())
    }

    private func conversation(title: String, path: String) -> Conversation {
        var conversation = Conversation(title: title, workspacePath: path)
        conversation.messages = [ChatMessage(role: "user", content: "Preserve this request.")]
        return conversation
    }

    private func persistedHistory(in directory: URL) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("conversations.json"))
    }
}
