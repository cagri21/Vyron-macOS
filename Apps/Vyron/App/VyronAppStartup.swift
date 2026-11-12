import Foundation

@MainActor
final class VyronAppStartup {
    private var completed = false
    private var stopped = false
    private var attempt: Task<Void, Never>?

    func run(_ prepare: @escaping @MainActor () async -> Bool) async {
        while !completed, !stopped, !Task.isCancelled {
            if let attempt {
                // A reopened window waits for the canceled attempt to release its shared dependencies.
                await attempt.value
                continue
            }
            let task = Task { @MainActor [weak self] in
                defer { self?.attempt = nil }
                guard !Task.isCancelled else { return }
                if await prepare() { self?.completed = true }
            }
            attempt = task
            await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            return
        }
    }

    func shutdown() -> Task<Void, Never>? {
        stopped = true
        let pending = attempt
        pending?.cancel()
        return pending
    }
}
