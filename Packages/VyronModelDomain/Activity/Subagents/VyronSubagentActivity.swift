import Foundation

public struct VyronSubagentActivity: Codable, Sendable, Equatable, Identifiable {
    public let identity: VyronSubagentIdentity
    public private(set) var activity: ResponseActivity
    public private(set) var summary: String?

    public var id: UUID { identity.id }

    public init(identity: VyronSubagentIdentity, startedAt: Date) {
        self.identity = identity
        activity = ResponseActivity(startedAt: startedAt)
        summary = nil
    }

    mutating func record(_ content: VyronActivityContent, at date: Date) {
        activity.record(content, at: date)
    }

    mutating func finish(_ state: ResponseActivity.State, summary: String?, at date: Date) {
        guard activity.state == .working, state != .working else { return }
        self.summary = summary.map { String($0.prefix(VyronActivityLimits.maximumSummaryCharacters)) }
        activity.finish(state, at: date)
    }
}
