import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronScheduledTasksModelTests: XCTestCase {
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("The scheduled operation did not reach the expected state.")
        throw CancellationError()
    }

    func testOccurrenceIsPersistedBeforeExecutionAndDoesNotReplayAfterReopen() async throws {
        let task = VyronScheduledTaskTestHarness.task()
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }

        test.model.tick()
        XCTAssertEqual(test.model.activeTaskID, task.id)
        let claimed = try XCTUnwrap(test.store.load().first)
        XCTAssertEqual(claimed.progress.lastRun?.state, .running)
        XCTAssertEqual(claimed.progress.lastRun?.scheduledAt, task.progress.nextRunAt)
        XCTAssertNil(claimed.progress.nextRunAt)
        try await waitUntil { test.executor.calls.count == 1 }
        test.model.tick()
        XCTAssertEqual(test.executor.calls.count, 1)

        test.model.shutdown()
        let reopened = VyronScheduledTasksModel(store: test.store, now: { test.clock.date })
        defer { reopened.shutdown() }
        var replayCount = 0
        reopened.configure(canRun: { true }) { _ in
            replayCount += 1
            return VyronScheduledTaskRunResult(state: .completed, conversationID: nil, detail: nil)
        }
        XCTAssertEqual(reopened.tasks.first?.progress.lastRun?.state, .interrupted)
        reopened.tick()
        await Task.yield()
        XCTAssertEqual(replayCount, 0)
        XCTAssertNil(reopened.activeTaskID)
    }

    func testBusyAppKeepsDueOccurrenceUntilItCanRun() async throws {
        let task = VyronScheduledTaskTestHarness.task()
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        test.executor.canRun = false
        test.model.tick()
        XCTAssertNil(test.model.activeTaskID)
        XCTAssertEqual(test.model.tasks.first?.progress.nextRunAt, task.progress.nextRunAt)
        XCTAssertNil(try test.store.load().first?.progress.lastRun)
        XCTAssertTrue(test.executor.calls.isEmpty)

        test.executor.canRun = true
        test.model.tick()
        try await waitUntil { test.executor.calls.count == 1 }
        test.executor.complete(VyronScheduledTaskRunResult(state: .completed, conversationID: nil, detail: nil))
        try await waitUntil { test.model.activeTaskID == nil }
        XCTAssertEqual(test.model.tasks.first?.progress.lastRun?.state, .completed)
    }

    func testMissedDailyOccurrencesCoalesceIntoOneRunWithFutureNextDate() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000 - 3 * 86_400)
        let task = VyronScheduledTaskTestHarness.task(startsAt: start, recurrence: .daily)
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        test.model.tick()
        try await waitUntil { test.executor.calls.count == 1 }
        let next = try XCTUnwrap(test.model.tasks.first?.progress.nextRunAt)
        XCTAssertGreaterThan(next, test.clock.date)
        XCTAssertEqual(next, task.schedule.nextRun(after: test.clock.date))
        test.executor.complete(VyronScheduledTaskRunResult(state: .completed, conversationID: nil, detail: nil))
        try await waitUntil { test.model.activeTaskID == nil }
        test.model.tick()
        await Task.yield()
        XCTAssertEqual(test.executor.calls.count, 1, "Missed days must not trigger a burst of old runs.")
    }

    func testPauseSurvivesReopenAndResumeAllowsTheNextOccurrence() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_060)
        let task = VyronScheduledTaskTestHarness.task(startsAt: start)
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        test.model.setEnabled(false, for: task.id)
        test.model.tick()
        XCTAssertFalse(try XCTUnwrap(test.store.load().first).progress.isEnabled)
        XCTAssertTrue(test.executor.calls.isEmpty)

        let reopened = VyronScheduledTasksModel(store: test.store, now: { test.clock.date })
        XCTAssertFalse(try XCTUnwrap(reopened.tasks.first).progress.isEnabled)
        reopened.shutdown()

        test.clock.date = start.addingTimeInterval(-1)
        test.model.setEnabled(true, for: task.id)
        XCTAssertTrue(try XCTUnwrap(test.model.tasks.first).progress.isEnabled)
        test.model.tick()
        XCTAssertTrue(test.executor.calls.isEmpty)
        test.clock.date = start.addingTimeInterval(1)
        test.model.tick()
        try await waitUntil { test.executor.calls.count == 1 }
    }

    func testFailedOccurrenceStaysConsumedUntilExplicitRunNow() async throws {
        let task = VyronScheduledTaskTestHarness.task()
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        test.model.tick()
        try await waitUntil { test.executor.calls.count == 1 }
        let originalRun = test.model.tasks.first?.progress.lastRun?.id
        test.executor.complete(
            VyronScheduledTaskRunResult(state: .failed, conversationID: nil, detail: "The model is unavailable.")
        )
        try await waitUntil { test.model.activeTaskID == nil }
        XCTAssertEqual(test.model.tasks.first?.progress.lastRun?.state, .failed)
        XCTAssertEqual(try test.store.load().first?.progress.lastRun?.state, .failed)
        test.model.tick()
        await Task.yield()
        XCTAssertEqual(test.executor.calls.count, 1)

        test.model.runNow(task.id)
        try await waitUntil { test.executor.calls.count == 2 }
        XCTAssertNotEqual(test.model.tasks.first?.progress.lastRun?.id, originalRun)
        let conversationID = UUID()
        test.executor.complete(
            VyronScheduledTaskRunResult(state: .completed, conversationID: conversationID, detail: nil)
        )
        try await waitUntil { test.model.activeTaskID == nil }
        XCTAssertEqual(test.model.tasks.first?.progress.lastRun?.output.conversationID, conversationID)
        XCTAssertEqual(test.model.tasks.first?.progress.lastRun?.state, .completed)
    }

    func testStopRetainsActiveOwnershipUntilSettlementAndIgnoresLateSuccess() async throws {
        let task = VyronScheduledTaskTestHarness.task()
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        test.model.tick()
        try await waitUntil { test.executor.calls.count == 1 }
        test.model.stop()
        XCTAssertEqual(test.model.activeTaskID, task.id)
        test.model.runNow(task.id)
        test.model.tick()
        XCTAssertEqual(test.executor.calls.count, 1)
        test.executor.complete(VyronScheduledTaskRunResult(state: .completed, conversationID: UUID(), detail: nil))
        try await waitUntil { test.model.activeTaskID == nil }
        XCTAssertEqual(test.model.tasks.first?.progress.lastRun?.state, .stopped)
        XCTAssertEqual(try test.store.load().first?.progress.lastRun?.state, .stopped)
    }

    func testActiveTaskCannotBeEditedOrRemoved() async throws {
        let task = VyronScheduledTaskTestHarness.task()
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        test.model.tick()
        try await waitUntil { test.executor.calls.count == 1 }
        var edited = try XCTUnwrap(test.model.tasks.first)
        edited.definition.title = "A replacement definition"
        XCTAssertFalse(test.model.save(edited))
        test.model.remove(task.id)
        XCTAssertEqual(test.model.tasks.count, 1)
        XCTAssertEqual(test.model.tasks.first?.definition.title, task.definition.title)
        XCTAssertEqual(try test.store.load().first?.definition.title, task.definition.title)
    }

    func testCorruptStorageIsPreservedAndPreventsMutationsOrExecution() throws {
        let original = Data("{invalid saved schedule, retain original".utf8)
        let test = try VyronScheduledTaskTestHarness(corruptData: original)
        addTeardownBlock { try await test.cleanUp() }
        let task = VyronScheduledTaskTestHarness.task()
        XCTAssertNotNil(test.model.errorMessage)
        XCTAssertFalse(test.model.save(task))
        test.model.remove(task.id)
        test.model.setEnabled(true, for: task.id)
        test.model.runNow(task.id)
        test.model.tick()
        XCTAssertTrue(test.model.tasks.isEmpty)
        XCTAssertTrue(test.executor.calls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: test.fileURL), original)
    }

    func testFailedDurableClaimDoesNotLaunchOrConsumeTheOccurrence() async throws {
        let task = VyronScheduledTaskTestHarness.task()
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        try FileManager.default.removeItem(at: test.fileURL)
        try FileManager.default.createDirectory(at: test.fileURL, withIntermediateDirectories: false)

        test.model.tick()
        await Task.yield()
        XCTAssertTrue(test.executor.calls.isEmpty)
        XCTAssertNil(test.model.activeTaskID)
        XCTAssertNil(test.model.tasks.first?.progress.lastRun)
        XCTAssertEqual(test.model.tasks.first?.progress.nextRunAt, task.progress.nextRunAt)
        XCTAssertNotNil(test.model.errorMessage)
    }

    func testEditorSaveChangesEnabledStateAndRetainsPreviousRunMetadata() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_060)
        var task = VyronScheduledTaskTestHarness.task(startsAt: start, recurrence: .daily)
        let previousRun = VyronScheduledTaskRun(
            id: UUID(),
            scheduledAt: start.addingTimeInterval(-86_400),
            state: .completed,
            output: VyronScheduledTaskRunOutput(
                startedAt: start.addingTimeInterval(-86_400),
                finishedAt: start.addingTimeInterval(-86_399),
                conversationID: UUID(),
                detail: "A previous result."
            )
        )
        task.progress.lastRun = previousRun
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        var edited = task
        edited.progress.isEnabled = false
        XCTAssertTrue(test.model.save(edited))
        XCTAssertFalse(try XCTUnwrap(test.store.load().first).progress.isEnabled)
        XCTAssertEqual(test.model.tasks.first?.progress.lastRun, previousRun)

        test.clock.date = start.addingTimeInterval(60)
        edited.progress.isEnabled = true
        XCTAssertTrue(test.model.save(edited))
        let saved = try XCTUnwrap(test.store.load().first)
        XCTAssertTrue(saved.progress.isEnabled)
        XCTAssertEqual(saved.progress.lastRun, previousRun)
        XCTAssertEqual(saved.progress.nextRunAt, task.schedule.nextRun(after: test.clock.date))
    }

    func testClockMovingBackwardDuringExecutionStillPersistsAValidCompletedRun() async throws {
        let task = VyronScheduledTaskTestHarness.task()
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        test.model.tick()
        try await waitUntil { test.executor.calls.count == 1 }
        let startedAt = try XCTUnwrap(test.model.tasks.first?.progress.lastRun?.output.startedAt)
        test.clock.date = startedAt.addingTimeInterval(-3_600)
        test.executor.complete(VyronScheduledTaskRunResult(state: .completed, conversationID: nil, detail: nil))
        await test.model.waitForCurrentRun()

        let saved = try XCTUnwrap(test.store.load().first?.progress.lastRun)
        XCTAssertEqual(saved.state, .completed)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(saved.output.finishedAt), startedAt)
        XCTAssertNil(test.model.errorMessage)
    }

    func testShutdownPreventsNewLaunchesEvenWhenTickOrRunNowAreCalled() async throws {
        let task = VyronScheduledTaskTestHarness.task()
        let test = try VyronScheduledTaskTestHarness(tasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        test.model.shutdown()
        test.model.tick()
        test.model.runNow(task.id)
        await Task.yield()
        XCTAssertTrue(test.executor.calls.isEmpty)
        XCTAssertNil(test.model.activeTaskID)
        XCTAssertNil(try test.store.load().first?.progress.lastRun)
    }
}
