import Foundation

public struct ModelPullProgress: Sendable, Equatable {
    public let status: String
    public let completed: Int64?
    public let total: Int64?
    package let phase: VyronModelPullPhase?
    public var fraction: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    public init(status: String, completed: Int64? = nil, total: Int64? = nil) {
        self.init(status: status, completed: completed, total: total, phase: nil)
    }

    package init(
        status: String,
        completed: Int64? = nil,
        total: Int64? = nil,
        phase: VyronModelPullPhase?
    ) {
        self.status = status
        self.completed = completed
        self.total = total
        self.phase = phase
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Existing clients compare the provider status and transfer counts.
        lhs.status == rhs.status && lhs.completed == rhs.completed && lhs.total == rhs.total
    }
}
