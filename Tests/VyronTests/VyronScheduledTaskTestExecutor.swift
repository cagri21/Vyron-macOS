import Foundation
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronScheduledTaskTestExecutor {
    var canRun = true
    private(set) var calls: [VyronScheduledTask] = []
    private var continuations: [CheckedContinuation<VyronScheduledTaskRunResult, Never>] = []

    func execute(_ task: VyronScheduledTask) async -> VyronScheduledTaskRunResult {
        calls.append(task)
        // Deliberately settle only when the test says so, including after cancellation.
        return await withCheckedContinuation { continuations.append($0) }
    }

    func complete(_ result: VyronScheduledTaskRunResult) {
        precondition(!continuations.isEmpty)
        continuations.removeFirst().resume(returning: result)
    }

    func completeOutstanding() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(
                returning: VyronScheduledTaskRunResult(state: .stopped, conversationID: nil, detail: nil)
            )
        }
    }
}
