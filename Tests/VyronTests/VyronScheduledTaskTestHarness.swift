import Foundation
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronScheduledTaskTestHarness {
    let directory: URL
    let clock: VyronScheduledTaskTestClock
    let executor: VyronScheduledTaskTestExecutor
    let model: VyronScheduledTasksModel

    var fileURL: URL { directory.appendingPathComponent("scheduled-tasks.json") }
    var store: VyronScheduledTaskStore { VyronScheduledTaskStore(fileURL: fileURL) }

    init(tasks: [VyronScheduledTask] = [], corruptData: Data? = nil) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronScheduleTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        let fileURL = directory.appendingPathComponent("scheduled-tasks.json")
        let store = VyronScheduledTaskStore(fileURL: fileURL)
        if let corruptData {
            try corruptData.write(to: fileURL)
        } else {
            try store.save(tasks)
        }
        let clock = VyronScheduledTaskTestClock()
        let executor = VyronScheduledTaskTestExecutor()
        self.clock = clock
        self.executor = executor
        model = VyronScheduledTasksModel(store: store, now: { clock.date })
        model.configure(canRun: { executor.canRun }, execute: { await executor.execute($0) })
    }

    func cleanUp() async throws {
        model.shutdown()
        executor.completeOutstanding()
        for _ in 0..<500 {
            if model.activeTaskID == nil { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        try FileManager.default.removeItem(at: directory)
    }

    static func task(
        startsAt: Date = Date(timeIntervalSince1970: 1_799_999_940),
        recurrence: VyronTaskRecurrence = .once
    ) -> VyronScheduledTask {
        let model = VyronScheduledModelSelection(
            connectionID: nil,
            model: "test-model",
            automaticallySelect: false,
            effort: .balanced
        )
        let context = VyronScheduledTaskContext(workspacePath: nil, mode: .chat, model: model)
        let definition = VyronScheduledTaskDefinition(
            title: "Scheduled project summary",
            prompt: "Explain a useful project idea.",
            context: context
        )
        let schedule = VyronTaskSchedule(
            startsAt: startsAt,
            recurrence: recurrence,
            timeZoneIdentifier: "UTC"
        )
        return VyronScheduledTask(
            id: UUID(),
            definition: definition,
            schedule: schedule,
            progress: VyronScheduledTaskProgress(isEnabled: true, nextRunAt: startsAt, lastRun: nil)
        )
    }
}
