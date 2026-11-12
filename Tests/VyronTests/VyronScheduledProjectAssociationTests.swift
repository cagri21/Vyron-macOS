import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronScheduledProjectAssociationTests: XCTestCase {
    func testScheduleSnapshotKeepsProjectIdentityAndSelectedSourceFolderSeparate() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.workspaceState.selectedProjectPath = "/Projects/StableProject"
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: "/Sources/SelectedFolder", isDirectory: true)

        let saved = test.model.scheduledTaskContext()
        test.model.workspaceState.selectedProjectPath = "/Projects/LaterSelection"
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: "/Sources/LaterFolder", isDirectory: true)

        XCTAssertEqual(saved.projectPath, "/Projects/StableProject")
        XCTAssertEqual(saved.workspacePath, "/Sources/SelectedFolder")
    }

    func testScheduledResultRetainsSavedProjectAndExecutionFolderWithoutChangingForeground() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let project = test.directory.appendingPathComponent("StableProject", isDirectory: true)
        let source = test.directory.appendingPathComponent("SelectedSource", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("Source inventory\n".utf8).write(to: source.appendingPathComponent("README.md"))
        try registerProject(project.path, source: source.path, model: test.model)
        var task = test.task()
        task.definition.context.projectPath = project.path
        task.definition.context.workspacePath = source.path
        task.definition.context.mode = .chat
        let selectedID = test.model.selectedConversationID
        let draft = test.model.composer.draft
        test.model.workspaceState.selectedProjectPath = "/Projects/Foreground"
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: "/Sources/Foreground", isDirectory: true)
        XCTAssertTrue(test.model.scheduledTasks.save(task))

        test.model.scheduledTasks.runNow(task.id)
        try await waitForRequests(1, provider: test.provider)
        let requests = await test.provider.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertTrue(request.messages.map(\.content).joined().contains("SelectedSource"))
        XCTAssertEqual(test.model.commandApprovalWorkspacePath, source.path)
        await test.provider.complete("Scheduled source result.")
        await test.model.scheduledTasks.waitForCurrentRun()

        let run = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun)
        XCTAssertEqual(run.state, .completed)
        let resultID = try XCTUnwrap(run.output.conversationID)
        let result = try XCTUnwrap(test.persistedConversations().first { $0.id == resultID })
        XCTAssertEqual(result.projectPath, project.path)
        XCTAssertEqual(result.workspacePath, source.path)
        XCTAssertTrue(test.model.sidebarProjectConversations(project.path).contains { $0.id == resultID })
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.contains(.project(source.path)))
        XCTAssertEqual(test.model.workspaceState.selectedProjectPath, "/Projects/Foreground")
        XCTAssertEqual(test.model.workspaceState.workspaceURL?.path, "/Sources/Foreground")
        XCTAssertEqual(test.model.selectedConversationID, selectedID)
        XCTAssertEqual(test.model.composer.draft, draft)
    }

    func testDevelopmentScheduleRejectsRemovedSourceBeforeCreatingChatOrCallingProvider() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let project = test.directory.appendingPathComponent("StableProject").path
        let keptSource = test.directory.appendingPathComponent("KeptSource").path
        let removedSource = test.directory.appendingPathComponent("RemovedSource").path
        try registerProject(project, source: keptSource, model: test.model)
        var task = test.task()
        task.definition.context.projectPath = project
        task.definition.context.workspacePath = removedSource
        task.definition.context.mode = .plan
        let conversationIDs = test.model.conversations.map(\.id)
        XCTAssertTrue(test.model.scheduledTasks.save(task))

        test.model.scheduledTasks.runNow(task.id)
        await test.model.scheduledTasks.waitForCurrentRun()

        let run = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun)
        XCTAssertEqual(run.state, .failed)
        XCTAssertEqual(run.output.detail, VyronSidebarText.sourceFolderRemoved)
        XCTAssertNil(run.output.conversationID)
        XCTAssertEqual(test.model.conversations.map(\.id), conversationIDs)
        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(test.model.isRunningScheduledTask)
    }

    private func registerProject(_ path: String, source: String, model: AppModel) throws {
        var organization = model.sidebarState.sidebarOrganization
        try organization.updateProject(path: path, name: "Stable project", sourceFolders: [source])
        try model.sidebarState.sidebarStore.save(organization)
        model.sidebarState.sidebarOrganization = organization
    }

    private func waitForRequests(_ count: Int, provider: VyronScheduledTestProvider) async throws {
        for _ in 0..<500 {
            if await provider.requests.count == count { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("The in-memory provider did not receive the scheduled request.")
        throw CancellationError()
    }
}
