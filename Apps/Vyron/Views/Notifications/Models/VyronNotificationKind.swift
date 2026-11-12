enum VyronNotificationKind: Codable, Hashable, Sendable {
    case working
    case completed
    case failed
    case attention(VyronNotificationAttentionID)

    var isAttention: Bool {
        if case .attention = self { return true }
        return false
    }
}
