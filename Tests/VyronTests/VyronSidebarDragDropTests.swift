import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronSidebarDragDropTests: XCTestCase {
    func testProjectsAndFoldersReorderBeforeAndAfterTheirPeers() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let paths = ["One", "Two", "Three"].map { test.directory.appendingPathComponent($0).path }
        prepare(test.model, projects: paths)
        let projects = paths.map { VyronSidebarRow.item(.project($0)) }
        let firstFolder = try addFolder("First", to: test.model)
        let secondFolder = try addFolder("Second", to: test.model)

        XCTAssertEqual(test.model.sidebarRows(in: .rootProjects), projects)
        let afterLast = VyronSidebarDestination(group: .rootProjects, position: .after(projects[2]))
        XCTAssertTrue(test.model.canMoveSidebarRow(projects[0], to: afterLast))
        XCTAssertTrue(test.model.moveSidebarRow(projects[0], to: afterLast))
        XCTAssertEqual(test.model.sidebarRows(in: .rootProjects), [projects[1], projects[2], projects[0]])

        let beforeFirst = VyronSidebarDestination(group: .rootProjects, position: .before(projects[1]))
        XCTAssertTrue(test.model.moveSidebarRow(projects[2], to: beforeFirst))
        let reorderedProjects = [projects[2], projects[1], projects[0]]
        XCTAssertEqual(test.model.sidebarRows(in: .rootProjects), reorderedProjects)

        let moveFolder = VyronSidebarDestination(group: .rootFolders, position: .before(.folder(firstFolder)))
        XCTAssertTrue(test.model.moveSidebarRow(.folder(secondFolder), to: moveFolder))
        XCTAssertEqual(test.model.sidebarRows(in: .rootFolders), [.folder(secondFolder), .folder(firstFolder)])

        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.scheduledTasks.shutdown() }
        XCTAssertEqual(reopened.sidebarRows(in: .rootFolders), [.folder(secondFolder), .folder(firstFolder)])
        XCTAssertEqual(reopened.sidebarRows(in: .rootProjects), reorderedProjects)
    }

    func testFolderMovesWithItsChildrenAndCannotMoveIntoItsDescendant() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let path = test.directory.appendingPathComponent("Project").path
        prepare(test.model, projects: [path])
        let parent = try addFolder("Parent", to: test.model)
        let child = try addFolder("Child", to: test.model, parent: parent)
        let destination = try addFolder("Destination", to: test.model)
        let project = VyronSidebarRow.item(.project(path))
        test.model.setSidebarFolderExpanded(destination.id, expanded: false)

        let invalidMove = VyronSidebarDestination(group: .folder(child), position: .end)
        let original = test.model.sidebarState.sidebarOrganization
        XCTAssertFalse(test.model.canMoveSidebarRow(.folder(parent), to: invalidMove))
        XCTAssertFalse(test.model.moveSidebarRow(.folder(parent), to: invalidMove))
        XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), original)

        let target = VyronSidebarDestination(group: .folder(destination), position: .end)
        XCTAssertTrue(test.model.moveSidebarRow(.folder(parent), to: target))
        let beforeParent = VyronSidebarDestination(group: .folder(destination), position: .before(.folder(parent)))
        XCTAssertTrue(test.model.moveSidebarRow(project, to: beforeParent))

        XCTAssertEqual(test.model.sidebarRows(in: .rootFolders), [.folder(destination)])
        XCTAssertEqual(test.model.sidebarRows(in: .folder(destination)), [project, .folder(parent)])
        XCTAssertEqual(test.model.sidebarRows(in: .folder(parent)), [.folder(child)])
        XCTAssertTrue(test.model.sidebarState.sidebarOrganization.isFolderExpanded(destination.id))
        XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), test.model.sidebarState.sidebarOrganization)
    }

    func testChatOrderAndDisplayMovesPersistWithoutChangingOwnershipOrHistory() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let originalPath = test.directory.appendingPathComponent("Original").path
        let destinationPath = test.directory.appendingPathComponent("Destination").path
        let source = test.directory.appendingPathComponent("Source").path
        var firstChat = Conversation(title: "First", workspacePath: source)
        firstChat.projectPath = originalPath
        firstChat.messages = [ChatMessage(role: "user", content: "Keep this request.")]
        let otherChat = Conversation(title: "Other chat", workspacePath: destinationPath)
        let moreRecentChat = Conversation(title: "More recent", workspacePath: destinationPath)
        prepare(test.model, projects: [originalPath, destinationPath], chats: [moreRecentChat, otherChat, firstChat])
        XCTAssertTrue(test.model.changeSidebar {
            try $0.updateProject(path: originalPath, name: "Original", sourceFolders: [source])
        })
        XCTAssertTrue(test.model.saveHistory())
        let historyURL = test.directory.appendingPathComponent("conversations.json")
        let originalHistory = try Data(contentsOf: historyURL)
        let originalGroup = VyronSidebarGroup.project(.init(path: originalPath))
        let destinationGroup = VyronSidebarGroup.project(.init(path: destinationPath))
        let first = VyronSidebarRow.item(.conversation(firstChat.id))
        let other = VyronSidebarRow.item(.conversation(otherChat.id))
        let moreRecent = VyronSidebarRow.item(.conversation(moreRecentChat.id))

        let root = VyronSidebarDestination(group: .rootChats, position: .end)
        XCTAssertTrue(test.model.moveSidebarRow(first, to: root))
        XCTAssertEqual(test.model.sidebarRows(in: .rootChats), [first])
        XCTAssertTrue(test.model.sidebarRows(in: originalGroup).isEmpty)

        let beforeOther = VyronSidebarDestination(group: destinationGroup, position: .before(other))
        XCTAssertTrue(test.model.moveSidebarRow(first, to: beforeOther))
        let beforeMoreRecent = VyronSidebarDestination(group: destinationGroup, position: .before(moreRecent))
        XCTAssertTrue(test.model.moveSidebarRow(other, to: beforeMoreRecent))
        XCTAssertEqual(test.model.sidebarRows(in: destinationGroup), [other, moreRecent, first])
        XCTAssertTrue(test.model.sidebarRows(in: .rootChats).isEmpty)
        XCTAssertEqual(test.model.sidebarProjectConversations(originalPath).map(\.id), [firstChat.id])
        XCTAssertEqual(try Data(contentsOf: historyURL), originalHistory)

        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.scheduledTasks.shutdown() }
        XCTAssertEqual(reopened.sidebarRows(in: destinationGroup), [other, moreRecent, first])
        XCTAssertEqual(reopened.sidebarConversation(firstChat.id)?.workspacePath, source)
        XCTAssertEqual(reopened.sidebarConversation(firstChat.id)?.projectPath, originalPath)
        XCTAssertEqual(reopened.sidebarConversation(firstChat.id)?.messages, firstChat.messages)
        reopened.selectConversation(firstChat.id, loadProject: false)
        XCTAssertEqual(reopened.selectedConversationID, firstChat.id)
        XCTAssertEqual(reopened.workspaceState.selectedProjectPath, originalPath)
    }

    func testFailedDropSaveLeavesPlacementAndOrderUnchanged() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let path = test.directory.appendingPathComponent("Project").path
        prepare(test.model, projects: [path])
        let folder = try addFolder("Destination", to: test.model)
        let original = test.model.sidebarState.sidebarOrganization
        let sidebarFile = test.model.sidebarState.sidebarStore.fileURL
        let unreadable = Data("{ unfinished sidebar".utf8)
        try unreadable.write(to: sidebarFile)

        let project = VyronSidebarRow.item(.project(path))
        let destination = VyronSidebarDestination(group: .folder(folder), position: .end)
        XCTAssertTrue(test.model.canMoveSidebarRow(project, to: destination))
        XCTAssertFalse(test.model.moveSidebarRow(project, to: destination))
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, original)
        XCTAssertEqual(try Data(contentsOf: sidebarFile), unreadable)
    }

    private func prepare(_ model: AppModel, projects: [String], chats: [Conversation] = []) {
        model.conversations = chats
        XCTAssertTrue(model.changeSidebar { organization in
            organization = SidebarOrganization()
            for path in projects { try organization.registerProject(path: path) }
            for chat in chats { organization.registerConversation(id: chat.id) }
        })
    }

    private func addFolder(
        _ name: String,
        to model: AppModel,
        parent: VyronSidebarFolderReference? = nil
    ) throws -> VyronSidebarFolderReference {
        let id = try XCTUnwrap(model.createSidebarFolder(name: name, parentID: parent?.id))
        return VyronSidebarFolderReference(id: id)
    }
}
