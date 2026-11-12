import Foundation

/// Identifies the exact draft already assigned to a destination by the handoff chooser.
struct VyronPreparedChatHandoffDraft {
    let destinationID: UUID
    let request: String
}
