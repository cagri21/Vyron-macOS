import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronQueueDrainRegressionTests: XCTestCase {
    func testPromptAddedWhileAQueuedTurnRunsStartsAfterThatTurnCompletes() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("First queued prompt")
        await test.provider.complete(0, answer: "Original response")
        try await waitUntil { await test.provider.requests.count == 2 }

        test.send("New prompt while the queue is running")
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.composer.draft = "Preserve this unsent draft"
        await test.provider.complete(1, answer: "First queued response")
        try await waitUntil { await test.provider.requests.count == 3 }

        let requests = await test.provider.requests
        XCTAssertEqual(requests[2].last?.content, "New prompt while the queue is running")
        XCTAssertEqual(test.model.messages.filter { $0.id == queuedID }.count, 1)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, "Preserve this unsent draft")
        await test.provider.complete(2, answer: "Last response")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testSavingAQueueEditAfterTheCurrentTurnFinishesResumesTheQueue() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("First queued prompt")
        test.send("Second queued prompt")
        await test.provider.complete(0, answer: "Original response")
        try await waitUntil { await test.provider.requests.count == 2 }
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)

        test.model.composer.draft = "Preserve this unsent draft"
        test.model.editQueuedMessage(queuedID)
        test.model.composer.draft = "Edited second prompt"
        await test.provider.complete(1, answer: "First queued response")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertTrue(test.model.composer.isEditingQueuedMessage)
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [queuedID])

        test.model.send()
        try await waitUntil { await test.provider.requests.count == 3 }
        let requests = await test.provider.requests
        XCTAssertEqual(requests[2].last?.content, "Edited second prompt")
        XCTAssertEqual(test.model.messages.filter { $0.id == queuedID }.map(\.content), ["Edited second prompt"])
        XCTAssertEqual(test.model.composer.draft, "Preserve this unsent draft")
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
    }

    func testCancelingAQueueEditAfterTheCurrentTurnFinishesResumesTheOriginalPrompt() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Keep the original queued prompt")
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.composer.draft = "Preserve this unsent draft"
        test.model.editQueuedMessage(queuedID)
        test.model.composer.draft = "Discard this queue edit"
        await test.provider.complete(0, answer: "Original response")
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        test.model.composer.cancelQueuedMessageEdit()
        try await waitUntil { await test.provider.requests.count == 2 }
        let requests = await test.provider.requests
        XCTAssertEqual(requests[1].last?.content, "Keep the original queued prompt")
        XCTAssertEqual(test.model.messages.filter { $0.id == queuedID }.count, 1)
        XCTAssertFalse(test.model.messages.contains { $0.content == "Discard this queue edit" })
        XCTAssertEqual(test.model.composer.draft, "Preserve this unsent draft")
    }

    func testDeletingTheEditedQueueHeadAfterCompletionAllowsTheFollowingPromptToRun() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Delete this queued prompt")
        test.send("Run the following queued prompt")
        let deletedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        let nextID = try XCTUnwrap(test.model.queuedMessages.last?.id)
        test.model.editQueuedMessage(deletedID)
        await test.provider.complete(0, answer: "Original response")
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        test.model.deleteQueuedMessage(deletedID)
        try await waitUntil { await test.provider.requests.count == 2 }
        let requests = await test.provider.requests
        XCTAssertEqual(requests[1].last?.content, "Run the following queued prompt")
        XCTAssertFalse(test.model.messages.contains { $0.id == deletedID })
        XCTAssertEqual(test.model.messages.filter { $0.id == nextID }.count, 1)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
    }

    func testCancelingAnEditAfterExplicitStopKeepsTheQueuePaused() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Wait for an explicit restart")
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.editQueuedMessage(queuedID)
        test.model.stopGeneration()
        try await waitUntil { await test.provider.cancellations == 1 }

        test.model.composer.cancelQueuedMessageEdit()
        await Task.yield()
        await Task.yield()
        let requests = await test.provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [queuedID])
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
    }

    func testNewWorkPromptQueuedDuringAnActiveQueuedTurnStartsAfterCompletion() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("Queue regression project.\n".utf8).write(to: project.appendingPathComponent("README.md"))
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .agent
        test.send("Inspect the project")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        test.send("Explain the first result")
        await test.provider.completeDevelopment(0, message: DevelopmentMessage(
            role: "assistant", content: "The project has a README."
        ))
        try await waitUntil { await test.provider.developmentRequests.count == 2 }

        test.send("Then describe the next validation step")
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.composer.draft = "Preserve this Work draft"
        await test.provider.completeDevelopment(1, message: DevelopmentMessage(
            role: "assistant", content: "The first result is a project overview."
        ))
        try await waitUntil { await test.provider.developmentRequests.count == 3 }

        let requests = await test.provider.developmentRequests
        let modes = await test.provider.developmentModes
        XCTAssertEqual(modes, [.plan, .agent, .agent])
        XCTAssertTrue(requests[2].contains { $0.content.contains("Then describe the next validation step") })
        XCTAssertEqual(test.model.messages.filter { $0.id == queuedID }.count, 1)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertTrue(test.model.composer.pendingSteeringIDs.isEmpty)
        XCTAssertEqual(test.model.composer.draft, "Preserve this Work draft")
        await test.provider.completeDevelopment(2, message: DevelopmentMessage(
            role: "assistant", content: "Run the existing checks."
        ))
        try await waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testQueueResumesWhenTemporaryWorkspaceLoadingEndsAfterCompletion() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Wait until the workspace is ready")
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.workspaceState.isLoadingWorkspace = true
        await test.provider.complete(0, answer: "Original response")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        await settleQueueDrain(in: test.model)
        let pausedRequests = await test.provider.requests
        XCTAssertEqual(pausedRequests.count, 1)
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [queuedID])

        test.model.workspaceState.isLoadingWorkspace = false
        try await waitUntil { await test.provider.requests.count == 2 }
        let resumedRequests = await test.provider.requests
        XCTAssertEqual(resumedRequests[1].last?.content, "Wait until the workspace is ready")
        XCTAssertEqual(test.model.messages.filter { $0.id == queuedID }.count, 1)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
    }

    func testSavingAnEditAfterAResponseErrorKeepsTheQueuePaused() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Wait for an explicit retry")
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.editQueuedMessage(queuedID)
        test.model.composer.draft = "Edited prompt after the error"
        await test.provider.fail(0)
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        test.model.send()
        await settleQueueDrain(in: test.model)
        let requests = await test.provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(test.model.queuedMessages.map(\.content), ["Edited prompt after the error"])
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [queuedID])
        XCTAssertFalse(test.model.composer.isEditingQueuedMessage)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
    }

    func testSwitchingChatsAfterCompletionWhileEditingDoesNotRestartTheOldQueue() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Keep this prompt in the original chat")
        let originalID = try XCTUnwrap(test.model.selectedConversationID)
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.editQueuedMessage(queuedID)
        await test.provider.complete(0, answer: "Original response")
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        var other = Conversation(title: "Other chat", workspacePath: nil)
        other.mode = ComposerMode.chat.rawValue
        test.model.conversations.append(other)
        test.model.selectConversation(other.id, loadProject: false)
        test.model.composer.draft = "A draft for the other chat"
        await settleQueueDrain(in: test.model)
        XCTAssertEqual(test.model.selectedConversationID, other.id)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)

        test.model.selectConversation(originalID, loadProject: false)
        await settleQueueDrain(in: test.model)
        let requests = await test.provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [queuedID])
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
    }

    func testQueueResumesAfterAScheduledTaskReleasesItsActiveSlot() async throws {
        let test = makeHarness()
        let executor = VyronScheduledTaskTestExecutor()
        test.model.scheduledTasks.configure(canRun: { true }, execute: { await executor.execute($0) })
        addTeardownBlock { @MainActor in
            test.model.scheduledTasks.shutdown()
            executor.completeOutstanding()
            await test.model.scheduledTasks.waitForCurrentRun()
            test.cleanUp()
        }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Continue after the scheduled task")
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.editQueuedMessage(queuedID)
        await test.provider.complete(0, answer: "Original response")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        await settleQueueDrain(in: test.model)

        let task = VyronScheduledTaskTestHarness.task(startsAt: Date().addingTimeInterval(3_600))
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        test.model.scheduledTasks.runNow(task.id)
        try await waitUntil { executor.calls.count == 1 }
        test.model.composer.cancelQueuedMessageEdit()
        await settleQueueDrain(in: test.model)
        let pausedRequests = await test.provider.requests
        XCTAssertEqual(pausedRequests.count, 1)
        XCTAssertEqual(test.model.scheduledTasks.activeTaskID, task.id)
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [queuedID])

        executor.complete(VyronScheduledTaskRunResult(state: .completed, conversationID: nil, detail: nil))
        await test.model.scheduledTasks.waitForCurrentRun()
        try await waitUntil { await test.provider.requests.count == 2 }
        let resumedRequests = await test.provider.requests
        XCTAssertEqual(resumedRequests[1].last?.content, "Continue after the scheduled task")
        XCTAssertEqual(test.model.messages.filter { $0.id == queuedID }.count, 1)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        await test.provider.complete(1, answer: "Queued response")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testFailedExplicitSendConsumesPendingAutomaticContinuationUntilExplicitRetry() async throws {
        let test = makeHarness()
        defer { test.cleanUp() }
        test.send("Original prompt")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Keep this queued prompt until storage recovers")
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.editQueuedMessage(queuedID)
        await test.provider.complete(0, answer: "Original response")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        await settleQueueDrain(in: test.model)

        test.model.historyIsWritable = false
        test.model.composer.cancelQueuedMessageEdit()
        test.model.steerQueuedMessage(queuedID)
        XCTAssertEqual(test.model.errorMessage, VyronStatusText.historyUnavailable)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        test.model.historyIsWritable = true
        await settleQueueDrain(in: test.model)
        let afterFailure = await test.provider.requests
        XCTAssertEqual(afterFailure.count, 1)
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [queuedID])
        XCTAssertFalse(test.model.messages.contains { $0.id == queuedID })

        test.model.steerQueuedMessage(queuedID)
        try await waitUntil { await test.provider.requests.count == 2 }
        let retriedRequests = await test.provider.requests
        XCTAssertEqual(retriedRequests[1].last?.content, "Keep this queued prompt until storage recovers")
        XCTAssertEqual(test.model.messages.filter { $0.id == queuedID }.count, 1)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
    }

    private func settleQueueDrain(in model: AppModel) async {
        await Task.yield()
        await model.composer.queuedMessageDrainTask?.value
        await Task.yield()
    }

    private func makeHarness() -> VyronQueueTestHarness {
        let test = VyronQueueTestHarness()
        test.model.computerWork.automaticRequestRouting = false
        test.model.skillContextLoader = { _ in .empty }
        return test
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Queue delivery did not reach its expected state")
        throw CancellationError()
    }
}
