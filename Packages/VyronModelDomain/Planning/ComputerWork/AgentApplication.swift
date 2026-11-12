import Foundation

public struct AgentApplication: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let isRunning: Bool

    public init(id: String, name: String, isRunning: Bool = true) {
        self.id = id
        self.name = name
        self.isRunning = isRunning
    }
}
