import Foundation
import os

/// The lock owns all mutable state, including cancellation before continuation installation.
final class VyronUserInputGate: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: VyronUserInputGateState())

    func install(_ continuation: CheckedContinuation<VyronUserInputResponse, any Error>) -> Bool {
        let result = state.withLock { state -> Result<VyronUserInputResponse, any Error>? in
            if let result = state.result { return result }
            state.continuation = continuation
            return nil
        }
        if let result {
            continuation.resume(with: result)
            return false
        }
        return true
    }

    func attach(_ worker: Task<Void, Never>) {
        let shouldCancel = state.withLock { state in
            guard state.result == nil else { return true }
            state.worker = worker
            return false
        }
        if shouldCancel { worker.cancel() }
    }

    func resolve(_ result: Result<VyronUserInputResponse, any Error>) {
        let pending = state.withLock { state -> VyronUserInputGateState? in
            guard state.result == nil else { return nil }
            let pending = state
            state.result = result
            state.continuation = nil
            state.worker = nil
            return pending
        }
        pending?.worker?.cancel()
        pending?.continuation?.resume(with: result)
    }
}
