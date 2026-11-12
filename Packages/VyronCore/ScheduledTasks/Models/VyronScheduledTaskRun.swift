import Foundation

public struct VyronScheduledTaskRun: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var scheduledAt: Date
    public var state: VyronScheduledTaskRunState
    public var output: VyronScheduledTaskRunOutput

    public init(id: UUID, scheduledAt: Date, state: VyronScheduledTaskRunState, output: VyronScheduledTaskRunOutput) {
        self.id = id
        self.scheduledAt = scheduledAt
        self.state = state
        self.output = output
    }
}
