import Foundation

struct VyronConnectionBalanceClock {
    let now: @MainActor () -> Date
    let sleep: @MainActor (Duration) async throws -> Void

    static var continuous: Self {
        Self(now: Date.init, sleep: { try await Task.sleep(for: $0) })
    }
}
