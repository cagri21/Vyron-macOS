import Foundation

struct VyronNotificationID: Codable, Hashable, Sendable {
    let target: VyronNotificationTarget
    let kind: VyronNotificationKind

    var conversationID: UUID? { target.conversationID }
    var responseID: UUID? { target.responseID }

    var sortKey: String {
        let event: String
        switch kind {
        case .working: event = "working"
        case .completed: event = "completed"
        case .failed: event = "failed"
        case .attention(let attention): event = "attention-" + attention.requestID.uuidString
        }
        return target.sortKey + "-" + event
    }
}
