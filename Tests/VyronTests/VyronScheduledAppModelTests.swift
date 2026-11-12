import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronScheduledAppModelTests: XCTestCase {
    private func waitForRequests(_ count: Int, provider: VyronScheduledTestProvider) async throws {
        for _ in 0..<500 {
            if await provider.requests.count == count { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("The in-memory provider did not receive the expected request.")
        throw CancellationError()
    }

    func testScheduledChatUsesSavedPromptAndModelWithoutReplacingDraftOrSelection() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let selectedID = test.model.selectedConversationID
        let draft = test.model.composer.draft
        let task = test.task()
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        test.model.modelSelection.selectedModel = "a-later-model-selection"
        test.model.modelSelection.models.append(LocalModel(name: "a-later-model-selection", size: 1))
        XCTAssertTrue(test.model.canSend)
        test.model.scheduledTasks.runNow(task.id)
        try await waitForRequests(1, provider: test.provider)

        let requests = await test.provider.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.model, "saved-model")
        XCTAssertEqual(request.messages.map(\.content), [task.definition.prompt])
        XCTAssertEqual(request.messages.map(\.role), ["user"])
        XCTAssertEqual(test.model.selectedConversationID, selectedID)
        XCTAssertEqual(test.model.composer.draft, draft)
        XCTAssertFalse(test.model.canSend, "Foreground sends must wait for the scheduled run to finish.")
        await test.provider.complete("The scheduled answer.")
        await test.model.scheduledTasks.waitForCurrentRun()

        let run = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun)
        XCTAssertEqual(run.state, .completed)
        let resultID = try XCTUnwrap(run.output.conversationID)
        XCTAssertNotEqual(resultID, selectedID)
        let result = try XCTUnwrap(test.model.conversations.first { $0.id == resultID })
        XCTAssertEqual(result.messages.map(\.content), [task.definition.prompt, "The scheduled answer."])
        XCTAssertEqual(result.messages.last?.activity?.state, .completed)
        XCTAssertEqual(test.model.selectedConversationID, selectedID)
        XCTAssertEqual(test.model.composer.draft, draft)
        XCTAssertEqual(test.model.modelSelection.selectedModel, "a-later-model-selection")
        XCTAssertEqual(test.model.scheduledTasks.tasks.first?.definition.context.model.model, "saved-model")
        let persisted = try test.persistedConversations()
        XCTAssertEqual(persisted.first { $0.id == resultID }?.messages, result.messages)
        XCTAssertNotNil(persisted.first { $0.id == selectedID })
    }

    func testFailureAndCancellationPersistSeparateResultActivities() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let task = test.task()
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        test.model.scheduledTasks.runNow(task.id)
        try await waitForRequests(1, provider: test.provider)
        await test.provider.fail()
        await test.model.scheduledTasks.waitForCurrentRun()

        let failedRun = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun)
        XCTAssertEqual(failedRun.state, .failed)
        let failedID = try XCTUnwrap(failedRun.output.conversationID)
        XCTAssertEqual(
            test.model.conversations.first { $0.id == failedID }?.messages.last?.activity?.state,
            .failed
        )
        test.model.scheduledTasks.runNow(task.id)
        try await waitForRequests(2, provider: test.provider)
        test.model.scheduledTasks.stop()
        await test.provider.complete("An answer arriving after cancellation.")
        await test.model.scheduledTasks.waitForCurrentRun()

        let stoppedRun = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun)
        XCTAssertEqual(stoppedRun.state, .stopped)
        let stoppedID = try XCTUnwrap(stoppedRun.output.conversationID)
        XCTAssertNotEqual(stoppedID, failedID)
        let stopped = try XCTUnwrap(test.model.conversations.first { $0.id == stoppedID })
        XCTAssertEqual(stopped.messages.last?.activity?.state, .stopped)
        XCTAssertFalse(stopped.messages.last?.content.contains("An answer arriving") == true)
        XCTAssertFalse(test.model.isRunningScheduledTask)
        let persisted = try test.persistedConversations()
        XCTAssertEqual(persisted.first { $0.id == failedID }?.messages.last?.activity?.state, .failed)
        XCTAssertEqual(persisted.first { $0.id == stoppedID }?.messages.last?.activity?.state, .stopped)
    }

    func testHistoryWriteFailurePreventsInferenceAndPreservesTheCurrentConversation() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let selectedID = test.model.selectedConversationID
        let task = test.task()
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        let historyURL = test.directory.appendingPathComponent("conversations.json")
        if FileManager.default.fileExists(atPath: historyURL.path) {
            try FileManager.default.removeItem(at: historyURL)
        }
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)

        test.model.scheduledTasks.runNow(task.id)
        await test.model.scheduledTasks.waitForCurrentRun()

        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(test.model.scheduledTasks.tasks.first?.progress.lastRun?.state, .failed)
        XCTAssertNil(test.model.scheduledTasks.tasks.first?.progress.lastRun?.output.conversationID)
        XCTAssertEqual(test.model.conversations.map(\.id), [try XCTUnwrap(selectedID)])
        XCTAssertEqual(test.model.selectedConversationID, selectedID)
        XCTAssertEqual(test.model.composer.draft, "Keep this unsent draft.")
        XCTAssertFalse(test.model.isRunningScheduledTask)
    }

    func testScheduledChatIncludesAndPersistsTheSavedProjectInventory() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let project = test.directory.appendingPathComponent("SavedProject", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fileContent = "UNREAD_FILE_CONTENT_FOR_INVENTORY_TEST"
        try Data(fileContent.utf8).write(to: project.appendingPathComponent("README.md"))
        var task = test.task()
        task.definition.context.workspacePath = project.path
        let foregroundProject = test.directory.appendingPathComponent("ForegroundProject", isDirectory: true)
        test.model.workspaceState.workspaceURL = foregroundProject
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        test.model.scheduledTasks.runNow(task.id)
        try await waitForRequests(1, provider: test.provider)

        XCTAssertEqual(test.model.commandApprovalWorkspacePath, project.path)

        let requests = await test.provider.requests
        let request = try XCTUnwrap(requests.first)
        let suppliedContext = request.messages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(suppliedContext.contains("README.md"))
        XCTAssertTrue(suppliedContext.contains("SavedProject"))
        XCTAssertTrue(suppliedContext.contains(task.definition.prompt))
        XCTAssertFalse(suppliedContext.contains(fileContent), "An inventory supplies names without reading file contents.")
        let resultID = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun?.output.conversationID)
        let inProgress = try XCTUnwrap(test.persistedConversations().first { $0.id == resultID })
        let user = try XCTUnwrap(inProgress.messages.first)
        XCTAssertEqual(user.content, task.definition.prompt)
        XCTAssertTrue(inProgress.contextByMessageID?[user.id.uuidString]?.contains("README.md") == true)
        XCTAssertEqual(inProgress.workspacePath, project.path)

        await test.provider.complete("A project-aware answer.")
        await test.model.scheduledTasks.waitForCurrentRun()
        XCTAssertEqual(test.model.commandApprovalWorkspacePath, foregroundProject.path)
        let persisted = try XCTUnwrap(test.persistedConversations().first { $0.id == resultID })
        XCTAssertEqual(persisted.contextByMessageID, inProgress.contextByMessageID)
        XCTAssertEqual(persisted.messages.last?.activity?.state, .completed)
    }

    func testOnlyRunningScheduledTaskCanAcceptItsApproval() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let task = test.task()
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        test.model.scheduledTasks.runNow(task.id)
        try await waitForRequests(1, provider: test.provider)
        let runID = try XCTUnwrap(test.model.scheduledTasks.reviewableRun?.id)

        for stopped in [false, true] {
            let approval = CommandApproval(command: "swift test", reason: "Review the scheduled project command.")
            let review = Task { await test.model.reviewDevelopmentCommand(approval, generationID: runID) }
            defer {
                test.model.respondToCommandApproval(false, approvalID: approval.id)
                review.cancel()
            }
            for _ in 0..<500 {
                if test.model.interactions.pendingCommandApproval?.id == approval.id { break }
                try await Task.sleep(for: .milliseconds(1))
            }
            let presentedApproval = try XCTUnwrap(test.model.interactions.pendingCommandApproval)
            XCTAssertEqual(presentedApproval.id, approval.id)
            if stopped { test.model.scheduledTasks.stop() }

            test.model.respondToCommandApproval(true, approvalID: approval.id)
            let approved = await review.value
            XCTAssertEqual(approved, !stopped)
        }
    }
}
