import Foundation
import VyronCore

/// Only explicit children of the nearest later root response belong to its user turn.
struct VyronConversationResponseOwnership {
    private let childMessageIDs: Set<UUID>

    init(messages: [ChatMessage]) {
        var children: Set<UUID> = []
        var nextResponseID: UUID?
        for message in messages.reversed() {
            if message.conversationRole == .assistant {
                if let owner = message.parentResponseID, owner == nextResponseID {
                    children.insert(message.id)
                } else {
                    // Foreign, orphaned and backward references retain ordinary legacy boundaries.
                    nextResponseID = message.parentResponseID == nil ? message.id : nil
                }
            } else if message.conversationRole == .user, let owner = message.parentResponseID, owner == nextResponseID {
                children.insert(message.id)
            }
        }
        childMessageIDs = children
    }

    func isChild(_ message: ChatMessage) -> Bool {
        childMessageIDs.contains(message.id)
    }
}
