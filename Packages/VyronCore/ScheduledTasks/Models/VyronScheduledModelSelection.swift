import Foundation

public struct VyronScheduledModelSelection: Codable, Equatable, Sendable {
    public var connectionID: UUID?
    public var model: String
    public var automaticallySelect: Bool
    public var effort: AgentEffort

    public init(connectionID: UUID?, model: String, automaticallySelect: Bool, effort: AgentEffort) {
        self.connectionID = connectionID
        self.model = model
        self.automaticallySelect = automaticallySelect
        self.effort = effort
    }
}
