import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronProjectSourceFolderTests: XCTestCase {
    func testLegacyHistoryFallsBackToWorkspaceIdentityAndSplitIdentityRoundTrips() throws {
        let original = conversation(title: "Legacy task", source: "/Projects/Legacy", owner: nil)
        let encoded = try JSONEncoder().encode(original)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "projectPath")

        let restoredLegacy = try JSONDecoder().decode(
            Conversation.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(restoredLegacy.projectPath)
        XCTAssertEqual(restoredLegacy.workspacePath, "/Projects/Legacy")
        XCTAssertEqual(restoredLegacy.sidebarProjectPath, "/Projects/Legacy")
        XCTAssertEqual(restoredLegacy.messages, original.messages)

        let split = conversation(title: "Split task", source: "/Sources/Server", owner: "/Projects/Product")
        let restoredSplit = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(split))
        XCTAssertEqual(restoredSplit.id, split.id)
        XCTAssertEqual(restoredSplit.workspacePath, "/Sources/Server")
        XCTAssertEqual(restoredSplit.projectPath, "/Projects/Product")
        XCTAssertEqual(restoredSplit.sidebarProjectPath, "/Projects/Product")
        XCTAssertEqual(restoredSplit.messages, split.messages)
    }

    func testRecentWorkspacePathsReadsAndUpdatesTheExistingDefaultsKey() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let previous = try folder("PreviousProject", in: test.directory)
        let next = try folder("NextProject", in: test.directory)
        let legacyKey = "recentWorkspacePaths"
        let defaults = UserDefaults.standard
        let savedValue = defaults.object(forKey: legacyKey)
        defer {
            if let savedValue { defaults.set(savedValue, forKey: legacyKey) }
            else { defaults.removeObject(forKey: legacyKey) }
        }
        defaults.set([previous.path], forKey: legacyKey)

        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.scheduledTasks.shutdown() }
        XCTAssertEqual(reopened.workspaceState.recentWorkspacePaths, [previous.path])

        await reopened.loadWorkspace(next)
        let expectedPaths = [next.path, previous.path]
        XCTAssertEqual(reopened.workspaceState.recentWorkspacePaths, expectedPaths)
        XCTAssertEqual(defaults.stringArray(forKey: legacyKey), expectedPaths)
    }

    func testProjectNameAndSourcesSaveTogetherAndRestoreSelectedOwnerAfterReopening() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let owner = try folder("Project", in: test.directory).path
        let first = try folder("FirstSource", in: test.directory).path
        let second = try folder("SecondSource", in: test.directory).path
        let chat = conversation(title: "Existing task", source: second, owner: owner)
        try prepare(test.model, conversations: [chat], projectPaths: [owner])
        let history = try persistedHistory(in: test.directory)

        XCTAssertTrue(test.model.saveSidebarProject(owner, name: "  Product  ", sourceFolders: [second, first]))
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: second, isDirectory: true)
        test.model.workspaceState.selectedProjectPath = owner
        UserDefaults.standard.set(second, forKey: VyronUserDefaultsKey.workspacePath.rawValue)
        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.scheduledTasks.shutdown() }

        XCTAssertEqual(reopened.sidebarProjectName(owner), "Product")
        XCTAssertEqual(reopened.sidebarProjectSourceFolders(owner), [second, first])
        XCTAssertEqual(reopened.sidebarState.sidebarOrganization.allProjects, [owner])
        XCTAssertEqual(reopened.workspaceState.selectedProjectPath, owner)
        XCTAssertEqual(reopened.workspaceState.workspaceURL?.path, second)
        XCTAssertEqual(reopened.conversations.first?.workspacePath, second)
        XCTAssertEqual(reopened.conversations.first?.projectPath, owner)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testInvalidSourceEditsLeaveSavedNameSourcesAndHistoryUnchanged() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let ownerURL = try folder("Project", in: test.directory)
        let otherURL = try folder("OtherSource", in: test.directory)
        let owner = ownerURL.path
        let chat = conversation(title: "Kept", source: owner, owner: owner)
        try prepare(test.model, conversations: [chat], projectPaths: [owner])
        let symbolic = test.directory.appendingPathComponent("SourceLink")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: otherURL)
        let missing = test.directory.appendingPathComponent("MissingSource").path
        let regularFile = test.directory.appendingPathComponent("NotAFolder.txt")
        try Data("A file is not a source folder.".utf8).write(to: regularFile)
        let original = test.model.sidebarState.sidebarOrganization
        let history = try persistedHistory(in: test.directory)
        let invalidSources = [
            [], [missing], [symbolic.path], [regularFile.path], [otherURL.path, otherURL.path],
            [otherURL.path, otherURL.appendingPathComponent("Child/..").path]
        ]

        for sources in invalidSources {
            XCTAssertFalse(test.model.saveSidebarProject(owner, name: "Must not be saved", sourceFolders: sources))
            XCTAssertEqual(test.model.sidebarState.sidebarOrganization, original)
            XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), original)
            XCTAssertEqual(try persistedHistory(in: test.directory), history)
        }
        XCTAssertFalse(test.model.saveSidebarProject(owner, name: "", sourceFolders: [otherURL.path]))
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, original)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testBusyProjectRejectsSourceChangesWhileAllowingNameOnlyEdits() throws {
        let test = VyronQueueTestHarness()
        defer {
            test.model.foregroundRun.stop()
            test.cleanUp()
        }
        let owner = try folder("Project", in: test.directory).path
        let secondary = try folder("Secondary", in: test.directory).path
        let chat = conversation(title: "Active task", source: owner, owner: owner)
        try prepare(test.model, conversations: [chat], projectPaths: [owner])
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: owner, isDirectory: true)
        test.model.workspaceState.selectedProjectPath = owner
        test.model.selectedConversationID = chat.id
        test.model.composer.draft = "Keep this follow-up."
        test.model.beginTestForegroundResponse()
        let original = test.model.sidebarState.sidebarOrganization
        let history = try persistedHistory(in: test.directory)

        XCTAssertFalse(test.model.saveSidebarProject(owner, name: "Rejected", sourceFolders: [secondary]))
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, original)
        XCTAssertTrue(test.model.saveSidebarProject(owner, name: "Renamed while busy", sourceFolders: [owner]))

        XCTAssertEqual(test.model.sidebarProjectName(owner), "Renamed while busy")
        XCTAssertEqual(test.model.sidebarProjectSourceFolders(owner), [owner])
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, owner)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, owner)
        XCTAssertEqual(test.model.selectedConversationID, chat.id)
        XCTAssertEqual(test.model.composer.draft, "Keep this follow-up.")
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testSecondarySourceChatsGroupAndArchiveByProjectOwner() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let owner = try folder("Project", in: test.directory).path
        let secondary = try folder("Secondary", in: test.directory).path
        let other = try folder("OtherProject", in: test.directory).path
        let primaryChat = conversation(title: "Primary", source: owner, owner: owner)
        let secondaryChat = conversation(title: "Secondary", source: secondary, owner: owner)
        let otherChat = conversation(title: "Other", source: secondary, owner: other)
        try prepare(test.model, conversations: [primaryChat, secondaryChat, otherChat], projectPaths: [owner, other])
        XCTAssertTrue(test.model.saveSidebarProject(owner, name: "Combined", sourceFolders: [owner, secondary]))
        let history = try persistedHistory(in: test.directory)

        XCTAssertEqual(test.model.sidebarProjectChats(owner).map(\.id), [primaryChat.id, secondaryChat.id])
        XCTAssertEqual(test.model.sidebarProjectConversations(owner).map(\.id), [primaryChat.id, secondaryChat.id])
        XCTAssertTrue(test.model.sidebarProjectConversations(secondary).isEmpty)
        XCTAssertEqual(test.model.sidebarProjectChats(other).map(\.id), [otherChat.id])
        XCTAssertTrue(test.model.archiveSidebarProject(owner))

        XCTAssertEqual(
            test.model.sidebarState.sidebarOrganization.archivedConversationIDs,
            [primaryChat.id, secondaryChat.id]
        )
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.isConversationArchived(otherChat.id))
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.contains(.project(secondary)))
        XCTAssertEqual(test.model.conversations.map(\.workspacePath), [owner, secondary, secondary])
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testRemovingProjectClearsSecondaryWorkspaceAndStableSelectionWithoutDeletingHistory() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let owner = try folder("Project", in: test.directory).path
        let secondaryURL = try folder("Secondary", in: test.directory)
        let sourceFile = secondaryURL.appendingPathComponent("Keep.swift")
        let contents = Data("let keep = true\n".utf8)
        try contents.write(to: sourceFile)
        let chat = conversation(title: "Kept task", source: secondaryURL.path, owner: owner)
        try prepare(test.model, conversations: [chat], projectPaths: [owner])
        XCTAssertTrue(test.model.saveSidebarProject(owner, name: "Product", sourceFolders: [secondaryURL.path]))
        test.model.workspaceState.workspaceURL = secondaryURL
        test.model.workspaceState.selectedProjectPath = owner
        test.model.selectedConversationID = chat.id
        UserDefaults.standard.set(secondaryURL.path, forKey: VyronUserDefaultsKey.workspacePath.rawValue)
        let history = try persistedHistory(in: test.directory)

        XCTAssertTrue(test.model.removeSidebarProject(owner))

        XCTAssertNil(test.model.workspaceState.selectedProjectPath)
        XCTAssertNil(test.model.workspaceState.workspaceURL)
        XCTAssertNil(test.model.selectedConversationID)
        XCTAssertNil(UserDefaults.standard.object(forKey: VyronUserDefaultsKey.workspacePath.rawValue))
        XCTAssertNil(UserDefaults.standard.object(forKey: VyronUserDefaultsKey.selectedSidebarProjectPath.rawValue))
        XCTAssertEqual(test.model.conversations.first?.projectPath, owner)
        XCTAssertEqual(test.model.conversations.first?.workspacePath, secondaryURL.path)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
        XCTAssertEqual(try Data(contentsOf: sourceFile), contents)
    }

    func testSelectingChatWithDetachedSourceRetainsOwnerWithoutLoadingTools() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let owner = try folder("Project", in: test.directory).path
        let detached = try folder("DetachedSource", in: test.directory).path
        let chat = conversation(title: "Historical task", source: detached, owner: owner)
        try prepare(test.model, conversations: [chat], projectPaths: [owner])
        let history = try persistedHistory(in: test.directory)

        test.model.selectConversation(chat.id)

        XCTAssertEqual(test.model.selectedConversationID, chat.id)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, owner)
        XCTAssertNil(test.model.workspaceState.workspaceURL)
        XCTAssertEqual(test.model.statusMessage, VyronSidebarText.sourceFolderRemoved)
        XCTAssertFalse(test.model.selectedProjectSourceFolderIsAttached)
        XCTAssertFalse(test.model.canAcceptConversationMessage(in: .agent))
        XCTAssertFalse(test.model.workspaceState.isLoadingWorkspace)
        XCTAssertTrue(test.model.workspaceState.developmentWorkspaces.isEmpty)
        XCTAssertTrue(test.model.inspector.developmentFiles.isEmpty)
        XCTAssertEqual(test.model.conversations.first?.workspacePath, detached)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testSourceSwitchStartsFreshChatAndSelectsTheRequestedRoot() throws {
        let test = VyronQueueTestHarness()
        defer {
            // Invalidate the queued load before yielding; this test only verifies synchronous selection.
            test.model.clearWorkspace()
            test.cleanUp()
        }
        let owner = try folder("Project", in: test.directory).path
        let secondary = try folder("Secondary", in: test.directory).path
        let chat = conversation(title: "Previous task", source: owner, owner: owner)
        try prepare(test.model, conversations: [chat], projectPaths: [owner])
        XCTAssertTrue(test.model.saveSidebarProject(owner, name: "Product", sourceFolders: [owner, secondary]))
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: owner, isDirectory: true)
        test.model.workspaceState.selectedProjectPath = owner
        test.model.selectedConversationID = chat.id
        test.model.composer.draft = "Previous chat's unfinished draft"
        let history = try persistedHistory(in: test.directory)

        test.model.openSidebarProjectSourceFolder(secondary, projectPath: owner)

        XCTAssertNil(test.model.selectedConversationID)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, owner)
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, secondary)
        XCTAssertTrue(test.model.workspaceState.isLoadingWorkspace)
        XCTAssertTrue(test.model.composer.draft.isEmpty)
        XCTAssertTrue(test.model.workspaceState.developmentWorkspaces.isEmpty)
        XCTAssertEqual(test.model.conversations.first?.workspacePath, owner)
        XCTAssertEqual(test.model.conversations.first?.projectPath, owner)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testLateLoadWithStaleConversationOrSelectionCannotReplaceCurrentRoot() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let owner = try folder("Project", in: test.directory).path
        let current = try folder("CurrentSource", in: test.directory).path
        let chat = conversation(title: "Current", source: current, owner: owner)
        try prepare(test.model, conversations: [chat], projectPaths: [owner])
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: current, isDirectory: true)
        test.model.workspaceState.selectedProjectPath = owner
        test.model.selectedConversationID = chat.id
        test.model.composer.draft = "Keep this draft."
        test.model.statusMessage = "Keep this status."
        let staleURL = test.directory.appendingPathComponent("MissingStaleRoot", isDirectory: true)

        await test.model.loadWorkspace(staleURL, expectedConversationID: UUID(), projectPath: owner)
        await test.model.loadWorkspace(staleURL, expectedSelectionID: UUID(), projectPath: owner)

        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, current)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, owner)
        XCTAssertEqual(test.model.selectedConversationID, chat.id)
        XCTAssertEqual(test.model.composer.draft, "Keep this draft.")
        XCTAssertEqual(test.model.statusMessage, "Keep this status.")
        XCTAssertNil(test.model.errorMessage)
        XCTAssertFalse(test.model.workspaceState.isLoadingWorkspace)
        XCTAssertTrue(test.model.workspaceState.developmentWorkspaces.isEmpty)
    }

    func testMissingSidebarRecoversHistoryOwnerAndSourcesWithoutDuplicatingActiveSource() throws {
        let test = VyronQueueTestHarness()
        defer {
            test.model.clearWorkspace()
            test.cleanUp()
        }
        let owner = try folder("Project", in: test.directory).path
        let historical = try folder("HistoricalSource", in: test.directory).path
        let active = try folder("ActiveSource", in: test.directory).path
        let chat = conversation(title: "Historical task", source: historical, owner: owner)
        try prepare(test.model, conversations: [chat], projectPaths: [])
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: active, isDirectory: true)
        test.model.workspaceState.selectedProjectPath = owner
        let history = try persistedHistory(in: test.directory)
        try FileManager.default.removeItem(at: test.model.sidebarState.sidebarStore.fileURL)
        test.model.sidebarState.sidebarOrganization = SidebarOrganization()

        test.model.loadSidebarOrganization()

        XCTAssertEqual(test.model.sidebarState.sidebarOrganization.allProjects, [owner])
        XCTAssertEqual(test.model.sidebarProjectSourceFolders(owner), [active, historical])
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.contains(.project(active)))
        XCTAssertEqual(test.model.sidebarProjectChats(owner).map(\.id), [chat.id])
        XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), test.model.sidebarState.sidebarOrganization)
        test.model.selectConversation(chat.id)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, owner)
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, historical)
        XCTAssertTrue(test.model.workspaceState.isLoadingWorkspace)
        XCTAssertNotEqual(test.model.statusMessage, VyronSidebarText.sourceFolderRemoved)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    func testCorruptSidebarRecoversOwnerAndSourcesWhilePreservingCorruptOriginal() throws {
        let test = VyronQueueTestHarness()
        defer {
            test.model.clearWorkspace()
            test.cleanUp()
        }
        let owner = try folder("Project", in: test.directory).path
        let historical = try folder("HistoricalSource", in: test.directory).path
        let active = try folder("ActiveSource", in: test.directory).path
        let chat = conversation(title: "Historical task", source: historical, owner: owner)
        try prepare(test.model, conversations: [chat], projectPaths: [])
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: active, isDirectory: true)
        test.model.workspaceState.selectedProjectPath = owner
        let history = try persistedHistory(in: test.directory)
        let corrupt = Data("{ invalid original sidebar".utf8)
        try corrupt.write(to: test.model.sidebarState.sidebarStore.fileURL)
        test.model.sidebarState.sidebarOrganization = SidebarOrganization()

        test.model.loadSidebarOrganization()

        XCTAssertEqual(test.model.sidebarState.sidebarOrganization.allProjects, [owner])
        XCTAssertEqual(test.model.sidebarProjectSourceFolders(owner), [active, historical])
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.contains(.project(active)))
        XCTAssertEqual(test.model.sidebarProjectChats(owner).map(\.id), [chat.id])
        XCTAssertNotNil(test.model.errorMessage)
        XCTAssertEqual(try Data(contentsOf: test.model.sidebarState.sidebarStore.fileURL), corrupt)
        test.model.selectConversation(chat.id)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, owner)
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, historical)
        XCTAssertTrue(test.model.workspaceState.isLoadingWorkspace)
        XCTAssertNotEqual(test.model.statusMessage, VyronSidebarText.sourceFolderRemoved)
        XCTAssertEqual(try Data(contentsOf: test.model.sidebarState.sidebarStore.fileURL), corrupt)
        XCTAssertEqual(try persistedHistory(in: test.directory), history)
    }

    private func prepare(_ model: AppModel, conversations: [Conversation], projectPaths: [String]) throws {
        UserDefaults.standard.removeObject(forKey: VyronUserDefaultsKey.workspacePath.rawValue)
        model.workspaceState.selectedProjectPath = nil
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

    private func folder(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func conversation(title: String, source: String, owner: String?) -> Conversation {
        var conversation = Conversation(title: title, workspacePath: source)
        conversation.projectPath = owner
        conversation.messages = [ChatMessage(role: "user", content: "Keep this request.")]
        return conversation
    }

    private func persistedHistory(in directory: URL) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("conversations.json"))
    }
}
