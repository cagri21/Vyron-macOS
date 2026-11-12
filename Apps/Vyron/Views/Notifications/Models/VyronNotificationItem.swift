import Foundation

struct VyronNotificationItem: Identifiable, Equatable, Sendable {
    let id: VyronNotificationID
    let content: VyronNotificationContent
    let date: Date
    let isRead: Bool

    var conversationID: UUID? { id.conversationID }
    var responseID: UUID? { id.responseID }
    var kind: VyronNotificationKind { id.kind }
    var isLive: Bool { kind == .working }
    var isUnread: Bool { !isRead && !isLive }
    var isPriority: Bool { isLive || kind.isAttention || isUnread }
}
