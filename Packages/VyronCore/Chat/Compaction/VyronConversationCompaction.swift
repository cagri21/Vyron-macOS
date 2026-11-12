import Foundation

/// A saved inference snapshot. The original conversation remains the authoritative, complete history.
public struct VyronConversationCompaction: Codable, Sendable, Equatable {
    public let summary: String
    public let throughMessageID: UUID
    public let createdAt: Date

    public init(summary: String, throughMessageID: UUID, createdAt: Date = Date()) {
        self.summary = summary
        self.throughMessageID = throughMessageID
        self.createdAt = createdAt
    }
}
