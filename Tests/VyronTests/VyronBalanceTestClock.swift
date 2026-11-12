import Foundation

@MainActor
final class VyronBalanceTestClock {
    private(set) var date = Date(timeIntervalSince1970: 1_800_000_000)
    private var waits: [UUID: VyronBalanceTestSleep] = [:]

    var deadlines: [Date] { waits.values.map(\.deadline).sorted() }
    var pendingSleepCount: Int { waits.count }

    func sleep(_ duration: Duration) async throws {
        try Task.checkCancellation()
        guard duration > .zero else { return }
        let id = UUID()
        let components = duration.components
        let interval = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waits[id] = VyronBalanceTestSleep(
                    deadline: date.addingTimeInterval(interval), continuation: continuation
                )
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in self?.cancel(id) }
        }
    }

    func advance(by interval: TimeInterval) {
        date = date.addingTimeInterval(interval)
        let ready = waits.filter { $0.value.deadline <= date }
        for (id, _) in ready { waits.removeValue(forKey: id) }
        for (_, sleep) in ready { sleep.continuation.resume() }
    }

    func cancelAll() {
        let pending = waits.values
        waits = [:]
        for sleep in pending { sleep.continuation.resume(throwing: CancellationError()) }
    }

    private func cancel(_ id: UUID) {
        waits.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}
