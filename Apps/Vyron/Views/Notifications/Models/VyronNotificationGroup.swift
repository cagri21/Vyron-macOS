struct VyronNotificationGroup: Identifiable, Equatable, Sendable {
    let id: VyronNotificationSection
    let items: [VyronNotificationItem]
}
