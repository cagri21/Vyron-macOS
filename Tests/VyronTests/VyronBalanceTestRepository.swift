import Foundation
import VyronCore

actor VyronBalanceTestRepository: VyronConnectionBalanceProviding {
    private(set) var requests: [VyronBalanceTestRequest] = []
    private(set) var cancelledRequests: Set<Int> = []
    private var pending: [Int: CheckedContinuation<VyronConnectionBalanceSnapshot, any Error>] = [:]

    func fetchBalance(
        for profile: ModelConnectionProfile,
        apiKey: String
    ) async throws -> VyronConnectionBalanceSnapshot {
        let index = requests.count
        requests.append(VyronBalanceTestRequest(
            profile: profile, usedFixtureCredential: apiKey == "fixture-balance-key"
        ))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[index] = $0 }
        } onCancel: {
            Task { await self.recordCancellation(index) }
        }
    }

    func complete(_ index: Int, with snapshot: VyronConnectionBalanceSnapshot) {
        pending.removeValue(forKey: index)?.resume(returning: snapshot)
    }

    func fail(_ index: Int, with error: any Error) {
        pending.removeValue(forKey: index)?.resume(throwing: error)
    }

    func finishAll() {
        let continuations = pending.values
        pending = [:]
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }

    private func recordCancellation(_ index: Int) { cancelledRequests.insert(index) }
}
