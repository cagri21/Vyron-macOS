import Foundation

struct VyronNotificationAttention: Sendable {
    let target: VyronNotificationTarget
    let attentionID: UUID
    let content: VyronNotificationContent
    let date: Date

    var id: VyronNotificationID {
        VyronNotificationID(target: target, kind: .attention(VyronNotificationAttentionID(requestID: attentionID)))
    }
}
