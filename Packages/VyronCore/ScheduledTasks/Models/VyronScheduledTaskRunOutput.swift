import Foundation

public struct VyronScheduledTaskRunOutput: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var finishedAt: Date?
    public var conversationID: UUID?
    public var detail: String?

    public init(startedAt: Date, finishedAt: Date?, conversationID: UUID?, detail: String?) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.conversationID = conversationID
        self.detail = detail
    }
}
