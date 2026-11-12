import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronSidebarProjectActivityTests: XCTestCase {
    func testScheduledProjectActivitySurvivesCollapseAndSelectingAnotherChat() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let project = test.directory.appendingPathComponent("StableProject").path
        let source = test.directory.appendingPathComponent("ExternalSource", isDirectory: true)
        let otherProject = test.directory.appendingPathComponent("OtherProject").path
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("Local source inventory.\n".utf8).write(to: source.appendingPathComponent("README.md"))
        var other = Conversation(title: "Another project's chat", workspacePath: nil)
        other.projectPath = otherProject
        other.mode = ComposerMode.chat.rawValue
        test.model.conversations.append(other)
        var organization = test.model.sidebarState.sidebarOrganization
        try organization.updateProject(path: project, name: "Stable project", sourceFolders: [source.path])
        try organization.registerProject(path: otherProject)
        organization.registerConversation(id: other.id)
        try test.model.sidebarState.sidebarStore.save(organization)
        test.model.sidebarState.sidebarOrganization = organization
        var task = test.task()
        task.definition.context.projectPath = project
        task.definition.context.workspacePath = source.path
        task.definition.context.mode = .chat
        XCTAssertTrue(test.model.scheduledTasks.save(task))

        test.model.scheduledTasks.runNow(task.id)
        try await waitUntil { await test.provider.requests.count == 1 }
        let resultID = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun?.output.conversationID)
        test.model.setSidebarProjectExpanded(project, expanded: false)

        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.isProjectExpanded(project))
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 1)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(source.path), 0)
        test.model.selectConversation(other.id)
        XCTAssertEqual(test.model.selectedConversationID, other.id)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 1)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(otherProject), 0)
        test.model.setSidebarProjectExpanded(project, expanded: true)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 1)
        test.model.setSidebarProjectExpanded(project, expanded: false)

        await test.provider.complete("The scheduled project work finished.")
        await test.model.scheduledTasks.waitForCurrentRun()

        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 0)
        XCTAssertFalse(test.model.sidebarState.sidebarOrganization.isProjectExpanded(project))
        XCTAssertEqual(
            test.model.conversations.first { $0.id == resultID }?.messages.last?.activity?.state,
            .completed
        )
    }

    func testActivityGroupsSourceFoldersByStableProjectAndCountsEachChatOnce() throws {
        let test = VyronQueueTestHarness()
        defer {
            test.model.foregroundRun.stop()
            test.model.computerWork.pendingAgentGoal = nil
            test.cleanUp()
        }
        let project = test.directory.appendingPathComponent("Project").path
        let sourceA = test.directory.appendingPathComponent("SourceA").path
        let sourceB = test.directory.appendingPathComponent("SourceB").path
        let otherProject = test.directory.appendingPathComponent("OtherProject").path
        let first = conversation(workspace: sourceA, project: project)
        let second = conversation(workspace: sourceB, project: project)
        let other = conversation(workspace: otherProject, project: nil)
        test.model.conversations = [first, second, other]
        test.model.selectedConversationID = other.id
        let firstResponse = VyronResponseIdentity(
            generationID: UUID(),
            conversationID: first.id, messageID: try XCTUnwrap(first.messages.last?.id)
        )
        test.model.foregroundRun.begin(firstResponse)
        test.model.computerWork.pendingAgentGoal = PendingAgentGoal(
            goal: "Pending local task", effort: .balanced,
            conversationID: second.id, messageID: try XCTUnwrap(second.messages.last?.id)
        )

        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 2)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(sourceA), 0)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(sourceB), 0)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(otherProject), 0)
        test.model.computerWork.pendingAgentGoal = PendingAgentGoal(
            goal: "Same active task", effort: .balanced,
            conversationID: first.id, messageID: try XCTUnwrap(first.messages.last?.id)
        )
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 1)

        test.model.computerWork.pendingAgentGoal = nil
        test.model.foregroundRun.complete(firstResponse.generationID)
        test.model.foregroundRun.begin(VyronResponseIdentity(
            generationID: UUID(),
            conversationID: other.id, messageID: try XCTUnwrap(other.messages.last?.id)
        ))
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 0)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(otherProject), 1)
    }

    func testStaleWorkingHistoryDoesNotCountAsActiveProjectWork() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project").path
        let first = conversation(workspace: project, project: nil)
        let second = conversation(workspace: test.directory.appendingPathComponent("Source").path, project: project)
        test.model.conversations = [first, second]
        test.model.selectedConversationID = first.id
        var organization = SidebarOrganization()
        try organization.registerProject(path: project)
        try test.model.sidebarState.sidebarStore.save(organization)
        test.model.sidebarState.sidebarOrganization = organization

        XCTAssertEqual(first.messages.last?.activity?.state, .working)
        XCTAssertEqual(second.messages.last?.activity?.state, .working)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 0)
        test.model.setSidebarProjectExpanded(project, expanded: false)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 0)
        test.model.setSidebarProjectExpanded(project, expanded: true)
        XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 0)
    }

    func testCompletedStoppedAndFailedForegroundRunsClearProjectActivity() async throws {
        for terminalState in [ResponseActivity.State.completed, .stopped, .failed] {
            let test = VyronQueueTestHarness()
            defer { test.cleanUp() }
            let project = test.directory.appendingPathComponent("Project").path
            var chat = Conversation(title: "Project task", workspacePath: project)
            chat.projectPath = project
            chat.mode = ComposerMode.chat.rawValue
            test.model.conversations = [chat]
            test.model.selectedConversationID = chat.id
            test.model.computerWork.automaticRequestRouting = false
            test.send("Explain the local project task.")
            try await waitUntil { await test.provider.requests.count == 1 }
            XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 1)

            switch terminalState {
            case .completed:
                await test.provider.complete(0, answer: "Project work finished.")
            case .stopped:
                test.model.stopGeneration()
            case .failed:
                await test.provider.fail(0)
            case .working:
                XCTFail("The fixture requires a terminal response state.")
            }
            try await waitUntil { !test.model.foregroundRun.isGenerating }

            XCTAssertEqual(test.model.messages.last?.activity?.state, terminalState)
            XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project), 0)
        }
    }

    func testStoppingAgentKeepsOriginalProjectOwnershipWhileNavigatingToAnotherChatOrNewTask() async throws {
        for startsNewTask in [false, true] {
            let test = VyronQueueTestHarness()
            defer { test.cleanUp() }
            let project = test.directory.appendingPathComponent("OriginalProject", isDirectory: true)
            let otherProject = test.directory.appendingPathComponent("OtherProject").path
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try Data("Local project notes.\n".utf8).write(to: project.appendingPathComponent("README.md"))
            await test.model.loadWorkspace(project)
            test.model.composer.mode = .agent
            test.model.computerWork.automaticRequestRouting = false
            test.send("Inspect the existing project without editing it.")
            try await waitUntil { await test.provider.developmentRequests.count == 1 }
            let originalID = try XCTUnwrap(test.model.selectedConversationID)
            var other = Conversation(title: "Other project chat", workspacePath: nil)
            other.projectPath = otherProject
            other.mode = ComposerMode.chat.rawValue
            test.model.conversations.append(other)
            XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project.path), 1)

            test.model.stopGeneration()
            XCTAssertTrue(test.model.foregroundRun.isStoppingDevelopment)
            XCTAssertEqual(test.model.foregroundRun.stoppingDevelopmentConversationID, originalID)
            if startsNewTask {
                test.model.newConversation()
                XCTAssertNil(test.model.selectedConversationID)
            } else {
                test.model.selectConversation(other.id)
                XCTAssertEqual(test.model.selectedConversationID, other.id)
            }

            XCTAssertTrue(test.model.foregroundRun.isStoppingDevelopment)
            XCTAssertEqual(test.model.foregroundRun.stoppingDevelopmentConversationID, originalID)
            XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project.path), 1)
            XCTAssertEqual(test.model.sidebarProjectActiveChatCount(otherProject), 0)
            try await waitUntil {
                let cancellations = await test.provider.developmentCancellations
                return cancellations == 1 && !test.model.foregroundRun.isStoppingDevelopment
            }
            XCTAssertNil(test.model.foregroundRun.stoppingDevelopmentConversationID)
            XCTAssertEqual(test.model.sidebarProjectActiveChatCount(project.path), 0)
            XCTAssertEqual(test.model.sidebarProjectActiveChatCount(otherProject), 0)
        }
    }

    private func conversation(workspace: String, project: String?) -> Conversation {
        var conversation = Conversation(title: "Project chat", workspacePath: workspace)
        conversation.projectPath = project
        conversation.mode = ComposerMode.chat.rawValue
        conversation.messages = [
            ChatMessage(role: "user", content: "A project request"),
            ChatMessage(role: "assistant", content: "Recorded progress", activity: ResponseActivity())
        ]
        return conversation
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The project activity operation did not reach its expected state.")
        throw CancellationError()
    }
}
