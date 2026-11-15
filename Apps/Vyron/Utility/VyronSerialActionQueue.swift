import Foundation

/// Runs one action at a time and keeps each action in its caller's task.
@MainActor
final class VyronSerialActionQueue {
    private var isExecuting = false
    private var waiters: [Waiter] = []

    func perform<Result: Sendable>(_ operation: @MainActor () async throws -> Result) async throws -> Result {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        let result = try await operation()
        try Task.checkCancellation()
        return result
    }

    private func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if isExecuting {
                    waiters.append(Waiter(id: id, continuation: continuation))
                } else {
                    isExecuting = true
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelWaiter(id) }
        }
    }

    private func release() {
        if waiters.isEmpty {
            isExecuting = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
