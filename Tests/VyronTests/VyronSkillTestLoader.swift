import Foundation
import VyronCore

actor VyronSkillTestLoader {
    private var continuations: [Int: CheckedContinuation<VyronSkillInventory, any Error>] = [:]
    private var waiting: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var requestCount = 0

    func load(_ roots: [VyronSkillRoot]) async throws -> VyronSkillInventory {
        let index = requestCount
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations[index] = continuation
            for count in waiting.keys.filter({ $0 <= requestCount }) {
                waiting.removeValue(forKey: count)?.forEach { $0.resume() }
            }
        }
    }

    func waitForRequestCount(_ count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { waiting[count, default: []].append($0) }
    }

    func complete(_ index: Int, result: Result<VyronSkillInventory, any Error>) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }
}
