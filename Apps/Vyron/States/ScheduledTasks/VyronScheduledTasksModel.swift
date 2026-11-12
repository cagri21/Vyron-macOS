import Combine
import Foundation
import VyronCore

@MainActor
final class VyronScheduledTasksModel: ObservableObject {
    @Published private(set) var tasks: [VyronScheduledTask] = []
    @Published var errorMessage: String?
    @Published private(set) var activeTaskID: UUID?
    private(set) var committedTerminalRunIDs: Set<UUID> = []

    private let store: VyronScheduledTaskStore
    private let now: @MainActor () -> Date
    private var canRun: (@MainActor () -> Bool)?
    private var execute: (@MainActor (VyronScheduledTask) async -> VyronScheduledTaskRunResult)?
    private var timer: Task<Void, Never>?
    private var execution: Task<Void, Never>?
    private var writable = true
    private var isShutDown = false
    private var stopRequested = false
    private static let pollingInterval: Duration = .seconds(15)

    init(store: VyronScheduledTaskStore, now: @escaping @MainActor () -> Date = Date.init) {
        self.store = store
        self.now = now
        do {
            tasks = try store.load()
            recordCommittedTerminalRuns()
            var recovered = false
            for index in tasks.indices where tasks[index].progress.lastRun?.state == .running {
                tasks[index].progress.lastRun?.state = .interrupted
                let startedAt = tasks[index].progress.lastRun?.output.startedAt ?? now()
                tasks[index].progress.lastRun?.output.finishedAt = max(now(), startedAt)
                tasks[index].progress.lastRun?.output.detail = VyronScheduledTaskText.interrupted
                recovered = true
            }
            if recovered { try store.save(tasks) }
        } catch {
            writable = false
            errorMessage = VyronScheduledTaskText.storageRecovery + " "
                + VyronScheduledTaskErrorMessage.message(for: error)
        }
    }

    func configure(
        canRun: @escaping @MainActor () -> Bool,
        execute: @escaping @MainActor (VyronScheduledTask) async -> VyronScheduledTaskRunResult
    ) {
        self.canRun = canRun
        self.execute = execute
    }

    func start() {
        guard timer == nil, !isShutDown else { return }
        tick()
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: Self.pollingInterval) } catch { return }
                guard let self, !self.isShutDown else { return }
                self.tick()
            }
        }
    }

    func tick() {
        guard writable, !isShutDown, activeTaskID == nil, execute != nil, canRun?() == true else { return }
        let date = now()
        let due = tasks.filter {
            $0.progress.isEnabled && $0.progress.nextRunAt.map { $0 <= date } == true
        }.sorted { ($0.progress.nextRunAt ?? .distantFuture) < ($1.progress.nextRunAt ?? .distantFuture) }
        if let task = due.first { launch(task, scheduledAt: task.progress.nextRunAt ?? date) }
    }

    @discardableResult
    func save(_ requested: VyronScheduledTask) -> Bool {
        guard writable, !isShutDown else { return false }
        guard activeTaskID != requested.id else {
            errorMessage = VyronScheduledTaskText.activeTaskLocked
            return false
        }
        do {
            var task = try requested.validated()
            let previous = tasks.first { $0.id == task.id }
            if let previous {
                task.progress = previous.progress
                task.progress.isEnabled = requested.progress.isEnabled
            }
            if previous == nil || previous?.schedule != task.schedule
                || (task.progress.isEnabled && previous?.progress.isEnabled == false) {
                let date = now()
                let next = task.schedule.startsAt > date
                    ? task.schedule.startsAt : task.schedule.nextRun(after: date)
                guard next != nil else { throw VyronScheduledTaskError.invalidSchedule }
                task.progress.nextRunAt = next
            }
            var updated = tasks.filter { $0.id != task.id }
            updated.append(task)
            return commit(updated)
        } catch {
            errorMessage = VyronScheduledTaskErrorMessage.message(for: error)
            return false
        }
    }

    func remove(_ id: UUID) {
        guard activeTaskID != id else {
            errorMessage = VyronScheduledTaskText.activeTaskLocked
            return
        }
        _ = commit(tasks.filter { $0.id != id })
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard activeTaskID != id else {
            errorMessage = VyronScheduledTaskText.activeTaskLocked
            return
        }
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var updated = tasks
        if enabled, !updated[index].progress.isEnabled {
            let task = updated[index]
            let next = task.schedule.startsAt > now()
                ? task.schedule.startsAt : task.schedule.nextRun(after: now())
            guard let next else {
                errorMessage = VyronScheduledTaskText.invalidSchedule
                return
            }
            updated[index].progress.nextRunAt = next
        }
        updated[index].progress.isEnabled = enabled
        _ = commit(updated)
    }

    func runNow(_ id: UUID) {
        guard writable, !isShutDown else { return }
        guard activeTaskID == nil, canRun?() == true, execute != nil else {
            errorMessage = VyronScheduledTaskText.schedulerBusy
            return
        }
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        launch(task, scheduledAt: now())
    }

    func stop() {
        guard activeTaskID != nil else { return }
        stopRequested = true
        execution?.cancel()
    }

    func shutdown() {
        isShutDown = true
        timer?.cancel()
        timer = nil
        stop()
    }

    func waitForCurrentRun() async {
        await execution?.value
    }

    var reviewableRun: VyronScheduledTaskRun? {
        guard !stopRequested, !isShutDown, let activeTaskID,
            let run = tasks.first(where: { $0.id == activeTaskID })?.progress.lastRun,
            run.state == .running
        else { return nil }
        return run
    }

    @discardableResult
    func attachConversation(_ conversationID: UUID, to runID: UUID) -> Bool {
        guard !stopRequested, !isShutDown,
            let index = tasks.firstIndex(where: { $0.id == activeTaskID }),
            tasks[index].progress.lastRun?.id == runID
        else { return false }
        var updated = tasks
        updated[index].progress.lastRun?.output.conversationID = conversationID
        return commit(updated)
    }

    private func launch(_ requested: VyronScheduledTask, scheduledAt: Date) {
        guard let execute, let index = tasks.firstIndex(where: { $0.id == requested.id }) else { return }
        let date = now()
        var task = requested
        let runID = UUID()
        task.progress.lastRun = VyronScheduledTaskRun(
            id: runID,
            scheduledAt: scheduledAt,
            state: .running,
            output: VyronScheduledTaskRunOutput(
                startedAt: date, finishedAt: nil, conversationID: nil, detail: nil
            )
        )
        // Claim the occurrence and coalesce missed recurrences before any side effect.
        task.progress.nextRunAt = task.schedule.nextRun(after: max(date, scheduledAt))
        if task.schedule.recurrence == .once {
            task.progress.isEnabled = false
            task.progress.nextRunAt = nil
        }
        var claimed = tasks
        claimed[index] = task
        guard commit(claimed) else { return }
        activeTaskID = task.id
        stopRequested = false
        execution = Task { @MainActor [weak self] in
            let result = await execute(task)
            guard let self else { return }
            self.finish(taskID: task.id, runID: runID, result: result)
        }
    }

    private func finish(taskID: UUID, runID: UUID, result: VyronScheduledTaskRunResult) {
        guard activeTaskID == taskID,
            let index = tasks.firstIndex(where: { $0.id == taskID }),
            tasks[index].progress.lastRun?.id == runID
        else { return }
        var finished = tasks
        let stopped = stopRequested || Task.isCancelled
        finished[index].progress.lastRun?.state = stopped ? .stopped : result.state
        let startedAt = finished[index].progress.lastRun?.output.startedAt ?? now()
        finished[index].progress.lastRun?.output.finishedAt = max(now(), startedAt)
        finished[index].progress.lastRun?.output.conversationID = result.conversationID
        finished[index].progress.lastRun?.output.detail = stopped ? VyronScheduledTaskText.stopped : result.detail
        do {
            try store.save(finished)
            tasks = finished
            recordCommittedTerminalRuns()
        } catch {
            // The durable running claim remains consumed. Halt further runs until recovery.
            tasks = finished
            writable = false
            errorMessage = VyronScheduledTaskText.storageSaveFailed + " "
                + VyronScheduledTaskErrorMessage.message(for: error)
        }
        execution = nil
        activeTaskID = nil
        stopRequested = false
    }

    @discardableResult
    private func commit(_ updated: [VyronScheduledTask]) -> Bool {
        guard writable, !isShutDown else { return false }
        do {
            try store.save(updated)
            tasks = updated
            recordCommittedTerminalRuns()
            errorMessage = nil
            return true
        } catch {
            errorMessage = VyronScheduledTaskText.storageSaveFailed + " "
                + VyronScheduledTaskErrorMessage.message(for: error)
            return false
        }
    }

    private func recordCommittedTerminalRuns() {
        committedTerminalRunIDs = Set(tasks.compactMap { task in
            guard let run = task.progress.lastRun, run.output.finishedAt != nil,
                run.state == .completed || run.state == .failed else { return nil }
            return run.id
        })
    }
}
