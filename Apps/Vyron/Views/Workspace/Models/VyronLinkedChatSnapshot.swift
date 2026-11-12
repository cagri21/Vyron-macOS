import Foundation

/// Visible saved text only; project context, images, queued drafts, and tool activity are excluded.
struct VyronLinkedChatSnapshot: Codable {
    let conversationID: UUID
    let title: String
    let text: String
}
