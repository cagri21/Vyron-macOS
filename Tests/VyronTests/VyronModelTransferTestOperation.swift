import Foundation
@testable import Vyron
import VyronCore

@MainActor
final class VyronModelTransferTestOperation {
    private var continuation: CheckedContinuation<String, any Error>?
    private var progress: (@Sendable (ModelPullProgress) -> Void)?
    private(set) var starts = 0
    private(set) var refreshes = 0
    private(set) var result: Result<String, any Error>?

    var operation: VyronModelTransferOperation {
        VyronModelTransferOperation(
            execute: { update in
                self.starts += 1
                self.progress = update
                return try await withCheckedThrowingContinuation { self.continuation = $0 }
            },
            refreshModels: { self.refreshes += 1 },
            complete: { self.result = $0 }
        )
    }

    func emit(_ update: ModelPullProgress) {
        progress?(update)
    }

    func finish(_ result: Result<String, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
