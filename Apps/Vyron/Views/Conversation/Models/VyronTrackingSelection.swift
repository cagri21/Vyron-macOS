import Foundation

struct VyronTrackingSelection: Equatable, Sendable {
    let revealID = UUID()
    let conversationID: UUID
    let messageID: UUID
    let subagentID: UUID?
    let entryID: UUID?
}
