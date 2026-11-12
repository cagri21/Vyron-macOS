import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronNotificationSchedulingTests: XCTestCase {
    func testRecoverySaveFailureStillRetainsEarlierSuccessfullyLoadedTerminalRun() throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronNotificationRecovery-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let realDirectory = directory.appendingPathComponent("Actual", isDirectory: true)
        let realFile = realDirectory.appendingPathComponent("scheduled-tasks.json")
        let now = Date()
        var terminal = VyronScheduledTaskTestHarness.task(startsAt: now.addingTimeInterval(3_600))
        let terminalRunID = UUID()
        terminal.progress.lastRun = VyronScheduledTaskRun(
            id: terminalRunID, scheduledAt: now.addingTimeInterval(-20), state: .failed,
            output: VyronScheduledTaskRunOutput(
                startedAt: now.addingTimeInterval(-20), finishedAt: now.addingTimeInterval(-10),
                conversationID: nil, detail: "A previously saved real failure."
            )
        )
        var running = VyronScheduledTaskTestHarness.task(startsAt: now.addingTimeInterval(3_600))
        let runningID = UUID()
        running.progress.lastRun = VyronScheduledTaskRun(
            id: runningID, scheduledAt: now.addingTimeInterval(-5), state: .running,
            output: VyronScheduledTaskRunOutput(
                startedAt: now.addingTimeInterval(-5), finishedAt: nil, conversationID: nil, detail: nil
            )
        )
        try VyronScheduledTaskStore(fileURL: realFile).save([terminal, running])
        let original = try Data(contentsOf: realFile)
        let linkedDirectory = directory.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: realDirectory)
        let store = VyronScheduledTaskStore(fileURL: linkedDirectory.appendingPathComponent("scheduled-tasks.json"))
        XCTAssertEqual(try store.load().count, 2)
        let model = VyronScheduledTasksModel(store: store)

        XCTAssertNotNil(model.errorMessage, "The recovery write must reject its linked storage directory.")
        XCTAssertTrue(model.committedTerminalRunIDs.contains(terminalRunID))
        XCTAssertFalse(model.committedTerminalRunIDs.contains(runningID))
        XCTAssertEqual(model.tasks.first { $0.id == terminal.id }?.progress.lastRun?.state, .failed)
        XCTAssertEqual(model.tasks.first { $0.id == running.id }?.progress.lastRun?.state, .interrupted)
        XCTAssertEqual(try Data(contentsOf: realFile), original)
    }

    func testFailedFinalSchedulerSaveDoesNotCreatePhantomTerminalCard() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let executor = VyronScheduledTaskTestExecutor()
        defer { executor.completeOutstanding() }
        test.model.scheduledTasks.configure(canRun: { true }, execute: { await executor.execute($0) })
        let task = test.task()
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        test.model.scheduledTasks.runNow(task.id)
        for _ in 0..<500 {
            if executor.calls.count == 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertEqual(executor.calls.count, 1)
        let runID = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun?.id)
        let file = test.directory.appendingPathComponent("scheduled-tasks.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)

        executor.complete(VyronScheduledTaskRunResult(
            state: .failed, conversationID: nil, detail: "A real execution result whose final save is blocked."
        ))
        await test.model.scheduledTasks.waitForCurrentRun()
        XCTAssertEqual(test.model.scheduledTasks.tasks.first?.progress.lastRun?.state, .failed)
        XCTAssertNotNil(test.model.scheduledTasks.tasks.first?.progress.lastRun?.output.finishedAt)
        XCTAssertFalse(test.model.scheduledTasks.committedTerminalRunIDs.contains(runID))
        XCTAssertNotNil(test.model.scheduledTasks.errorMessage)
        XCTAssertTrue(test.model.notificationItems.isEmpty)
        XCTAssertEqual(test.model.unreadNotificationCount, 0)
        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testFailedScheduledRunWithoutConversationRoutesOnlyToSavedScheduler() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let selectedID = test.model.selectedConversationID
        let draft = test.model.composer.draft
        let task = test.task()
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        let history = test.directory.appendingPathComponent("conversations.json")
        if FileManager.default.fileExists(atPath: history.path) { try FileManager.default.removeItem(at: history) }
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)

        test.model.scheduledTasks.runNow(task.id)
        await test.model.scheduledTasks.waitForCurrentRun()
        let run = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun)
        XCTAssertEqual(run.state, .failed)
        XCTAssertNil(run.output.conversationID)
        XCTAssertNotNil(run.output.finishedAt)
        let item = try XCTUnwrap(test.model.notificationItems.first)
        XCTAssertEqual(item.id.target, .scheduledRun(VyronNotificationScheduledRunID(taskID: task.id, runID: run.id)))
        XCTAssertEqual(item.kind, .failed)
        XCTAssertNil(item.conversationID)
        XCTAssertNil(item.responseID)
        XCTAssertNil(test.model.notificationWindowTarget(item))

        XCTAssertTrue(test.model.openNotification(item))
        XCTAssertTrue(test.model.appNavigation.showScheduledTasks)
        XCTAssertEqual(test.model.selectedConversationID, selectedID)
        XCTAssertEqual(test.model.composer.draft, draft)
        XCTAssertTrue(test.model.notifications.readState.isRead(item.id))
        XCTAssertNil(test.model.scheduledTasks.activeTaskID)
        XCTAssertEqual(test.model.conversations.map(\.id), [try XCTUnwrap(selectedID)])
        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertFalse(test.model.isRunningScheduledTask)
    }
}
