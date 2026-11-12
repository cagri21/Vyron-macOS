import Foundation

/// Additional user guidance for one active development run.
public struct VyronSteeringMessage: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let content: String

    public init(id: UUID = UUID(), content: String) {
        self.id = id
        self.content = content
    }
}
