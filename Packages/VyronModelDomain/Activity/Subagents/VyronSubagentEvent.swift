import Foundation

public struct VyronSubagentEvent: Sendable {
    public let identity: VyronSubagentIdentity
    public let update: VyronSubagentUpdate
    public let date: Date

    public init(identity: VyronSubagentIdentity, update: VyronSubagentUpdate, date: Date = Date()) {
        self.identity = identity
        self.update = update
        self.date = date
    }
}
