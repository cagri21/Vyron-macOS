import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronProjectSetupIntegrationTests: XCTestCase {
    private let setupPaths = ["AGENTS.md", "README.md", "PLANS.md", ".gitignore"]

    func testExplicitProjectAddCreatesGuidanceBeforeLoadingFileInventory() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = try folder("AddedProject", in: test.directory)
        let selectionID = select(project, model: test.model)

        await test.model.loadAddedWorkspace(project, expectedSelectionID: selectionID)

        assertSetupFilesExist(in: project)
        let documentPaths: Set<String> = ["AGENTS.md", "README.md", "PLANS.md"]
        XCTAssertTrue(documentPaths.isSubset(of: Set(test.model.workspaceState.workspaceFiles.map(\.path))))
        XCTAssertTrue(documentPaths.isSubset(of: Set(test.model.inspector.developmentFiles.map(\.path))))
        XCTAssertEqual(test.model.workspaceState.workspaceURL, project)
        XCTAssertNotNil(test.model.workspaceState.developmentWorkspaces[project.path])
        XCTAssertFalse(test.model.workspaceState.isLoadingWorkspace)
        XCTAssertNil(test.model.errorMessage)
    }

    func testRepeatedExplicitAddPreservesExistingGuidanceBytes() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = try folder("ExistingProject", in: test.directory)
        let original = Dictionary(uniqueKeysWithValues: setupPaths.map { path in
            (path, Data("Existing user content in \(path).\r\nKeep this exact text.\r\n".utf8))
        })
        for (path, bytes) in original {
            try bytes.write(to: project.appendingPathComponent(path))
        }

        for _ in 0..<2 {
            let selectionID = select(project, model: test.model)
            await test.model.loadAddedWorkspace(project, expectedSelectionID: selectionID)
        }

        for (path, bytes) in original {
            XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent(path)), bytes, path)
        }
        XCTAssertEqual(test.model.workspaceState.workspaceURL, project)
        XCTAssertNil(test.model.errorMessage)
    }

    func testPassiveWorkspaceLoadDoesNotCreateGuidance() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = try folder("ReopenedProject", in: test.directory)
        test.model.composer.mode = .plan

        await test.model.loadWorkspace(project)

        assertSetupFilesAbsent(in: project)
        XCTAssertEqual(test.model.workspaceState.workspaceURL, project)
        XCTAssertNotNil(test.model.workspaceState.developmentWorkspaces[project.path])
        XCTAssertFalse(test.model.workspaceState.isLoadingWorkspace)
    }

    func testStaleExplicitAddDoesNotWriteFilesOrReplaceCurrentSelection() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let staleProject = try folder("StaleProject", in: test.directory)
        let currentProject = try folder("CurrentProject", in: test.directory)
        let currentSelectionID = select(currentProject, model: test.model)
        let staleSelectionID = UUID()

        await test.model.loadAddedWorkspace(staleProject, expectedSelectionID: staleSelectionID)

        assertSetupFilesAbsent(in: staleProject)
        assertSetupFilesAbsent(in: currentProject)
        XCTAssertEqual(test.model.composerAttachments.generation, currentSelectionID)
        XCTAssertEqual(test.model.workspaceState.workspaceURL, currentProject)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, currentProject.path)
        XCTAssertNil(test.model.errorMessage)
    }

    func testSavingNewSourceFolderInitializesOnlyTheNewFolder() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let owner = try folder("ProjectOwner", in: test.directory)
        let existing = try folder("ExistingSource", in: test.directory)
        let added = try folder("AddedSource", in: test.directory)
        try register(owner, sourceFolders: [existing.path], model: test.model)

        XCTAssertTrue(test.model.saveSidebarProject(
            owner.path,
            name: "Product",
            sourceFolders: [existing.path, added.path]
        ))

        assertSetupFilesExist(in: added)
        assertSetupFilesAbsent(in: existing)
        assertSetupFilesAbsent(in: owner)
        XCTAssertEqual(test.model.sidebarProjectSourceFolders(owner.path), [existing.path, added.path])
        XCTAssertNil(test.model.workspaceState.workspaceURL)
        XCTAssertNil(test.model.errorMessage)
    }

    func testInvalidProjectNameDoesNotInitializeProposedSourceFolder() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let owner = try folder("ProjectOwner", in: test.directory)
        let existing = try folder("ExistingSource", in: test.directory)
        let added = try folder("RejectedSource", in: test.directory)
        try register(owner, sourceFolders: [existing.path], model: test.model)
        let original = test.model.sidebarState.sidebarOrganization

        XCTAssertFalse(test.model.saveSidebarProject(
            owner.path,
            name: "   ",
            sourceFolders: [existing.path, added.path]
        ))

        assertSetupFilesAbsent(in: added)
        assertSetupFilesAbsent(in: existing)
        assertSetupFilesAbsent(in: owner)
        XCTAssertEqual(test.model.sidebarState.sidebarOrganization, original)
        XCTAssertEqual(try test.model.sidebarState.sidebarStore.load(), original)
        XCTAssertNotNil(test.model.errorMessage)
    }

    func testNameOnlySaveDoesNotInitializeExistingSourceFolder() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let owner = try folder("ProjectOwner", in: test.directory)
        let existing = try folder("ExistingSource", in: test.directory)
        try register(owner, sourceFolders: [existing.path], model: test.model)

        XCTAssertTrue(test.model.saveSidebarProject(owner.path, name: "Renamed", sourceFolders: [existing.path]))

        assertSetupFilesAbsent(in: existing)
        assertSetupFilesAbsent(in: owner)
        XCTAssertEqual(test.model.sidebarProjectName(owner.path), "Renamed")
    }

    func testReadOnlyProjectAddReportsSetupFailureAndStillLoadsProject() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = try folder("ReadOnlyProject", in: test.directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: project.path)
        defer { restorePermissions(in: project) }
        let selectionID = select(project, model: test.model)

        await test.model.loadAddedWorkspace(project, expectedSelectionID: selectionID)

        assertSetupFilesAbsent(in: project)
        let error = try XCTUnwrap(test.model.errorMessage)
        XCTAssertTrue(error.hasPrefix(VyronWorkspaceText.projectSetupFailure("")))
        XCTAssertTrue(error.contains(project.lastPathComponent))
        XCTAssertEqual(test.model.workspaceState.workspaceURL, project)
        XCTAssertNotNil(test.model.workspaceState.developmentWorkspaces[project.path])
        XCTAssertFalse(test.model.workspaceState.isLoadingWorkspace)
    }

    func testReplacingActiveSourceWithReadOnlyFolderRetainsSetupFailureAfterSwitch() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let owner = try folder("ProjectOwner", in: test.directory)
        let existing = try folder("ExistingSource", in: test.directory)
        let added = try folder("ReadOnlySource", in: test.directory)
        try register(owner, sourceFolders: [existing.path], model: test.model)
        await test.model.loadWorkspace(existing, projectPath: owner.path)
        var conversation = Conversation(title: "Previous task", workspacePath: existing.path)
        conversation.projectPath = owner.path
        conversation.messages = [ChatMessage(role: "user", content: "Keep the previous task.")]
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: added.path)
        defer { restorePermissions(in: added) }

        XCTAssertTrue(test.model.saveSidebarProject(owner.path, name: "Product", sourceFolders: [added.path]))

        let immediateError = try XCTUnwrap(test.model.errorMessage)
        XCTAssertTrue(immediateError.hasPrefix(VyronWorkspaceText.projectSetupFailure("")))
        XCTAssertNil(test.model.selectedConversationID)
        try await waitForWorkspaceLoad(test.model)

        assertSetupFilesAbsent(in: added)
        XCTAssertEqual(test.model.errorMessage, immediateError)
        XCTAssertEqual(test.model.workspaceState.workspaceURL, added)
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, owner.path)
        XCTAssertNotNil(test.model.workspaceState.developmentWorkspaces[added.path])
        XCTAssertEqual(test.model.sidebarProjectSourceFolders(owner.path), [added.path])
        XCTAssertEqual(test.model.conversations.first?.id, conversation.id)
    }

    private func select(_ project: URL, model: AppModel) -> UUID {
        let selectionID = UUID()
        model.composerAttachments.generation = selectionID
        model.workspaceState.workspaceURL = project
        model.workspaceState.selectedProjectPath = project.path
        model.workspaceState.isLoadingWorkspace = true
        return selectionID
    }

    private func folder(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func register(_ owner: URL, sourceFolders: [String], model: AppModel) throws {
        var organization = SidebarOrganization()
        try organization.updateProject(path: owner.path, name: "Product", sourceFolders: sourceFolders)
        try model.sidebarState.sidebarStore.save(organization)
        model.sidebarState.sidebarOrganization = organization
    }

    private func waitForWorkspaceLoad(_ model: AppModel) async throws {
        for _ in 0..<500 {
            if !model.workspaceState.isLoadingWorkspace { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The selected source folder did not finish loading.")
        throw CancellationError()
    }

    private func restorePermissions(in directory: URL) {
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        } catch {
            XCTFail("Could not restore test folder permissions before cleanup: \(error)")
        }
    }

    private func assertSetupFilesExist(in directory: URL) {
        for path in setupPaths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path), path)
        }
    }

    private func assertSetupFilesAbsent(in directory: URL) {
        for path in setupPaths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path), path)
        }
    }
}
