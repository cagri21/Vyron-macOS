import Foundation

/// Lets startup finish reading a credential after its owning selection has changed.
actor VyronConnectionPreparationTestReader {
    private(set) var requests: [UUID] = []
    private var waiters: [Int: CheckedContinuation<String, any Error>] = [:]

    func read(_ id: UUID) async throws -> String {
        let index = requests.count
        requests.append(id)
        return try await withCheckedThrowingContinuation { continuation in
            waiters[index] = continuation
        }
    }

    func complete(_ index: Int, result: Result<String, any Error>) -> Bool {
        guard let continuation = waiters.removeValue(forKey: index) else { return false }
        continuation.resume(with: result)
        return true
    }

    func cancelAll() {
        let pending = waiters.values
        waiters.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
    }
}
