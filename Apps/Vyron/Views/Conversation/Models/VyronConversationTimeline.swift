import Foundation
import VyronCore

struct VyronConversationTimeline: Sendable {
    let startDatesByMessageID: [UUID: Date]

    init(messages: [ChatMessage]) {
        var starts: [UUID: Date] = [:]
        var firstUserID: UUID?
        let ownership = VyronConversationResponseOwnership(messages: messages)
        for message in messages {
            if ownership.isChild(message) { continue }
            if message.conversationRole == .user {
                if firstUserID == nil { firstUserID = message.id }
            } else if message.conversationRole == .assistant {
                if let userID = firstUserID, let activity = message.activity {
                    starts[userID] = activity.startedAt
                }
                firstUserID = nil
            }
        }
        startDatesByMessageID = starts
    }
}
