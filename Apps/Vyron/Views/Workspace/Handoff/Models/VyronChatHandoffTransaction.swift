import Foundation
import VyronCore

struct VyronChatHandoffTransaction {
    let destination: Conversation
    let previousDestination: Conversation?
    let sourceID: UUID

    func matches(_ current: Conversation) -> Bool {
        current.id == destination.id && current.messages == destination.messages
            && current.queuedMessages == destination.queuedMessages && current.updatedAt == destination.updatedAt
            && current.title == destination.title && current.workspacePath == destination.workspacePath
            && current.projectPath == destination.projectPath && current.mode == destination.mode
            && current.isUnread == destination.isUnread
            && current.contextByMessageID == destination.contextByMessageID
            && current.compaction?.summary == destination.compaction?.summary
            && current.compaction?.throughMessageID == destination.compaction?.throughMessageID
            && current.compaction?.createdAt == destination.compaction?.createdAt
    }
}
