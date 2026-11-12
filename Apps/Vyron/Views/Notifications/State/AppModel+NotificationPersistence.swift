import Foundation

extension AppModel {
    func reloadNotificationReadState() {
        notifications.reloadReadState()
    }

    func configureNotificationObservers() {
        notifications.observe(
            mcpConnections,
            scheduledTasks: scheduledTasks,
            recordReview: { [weak self] id in self?.recordNotificationReview(id) },
            isActive: { [weak self] in self?.isShuttingDown == false }
        )
    }

    func recordNotificationReview(_ id: UUID?) {
        guard !isShuttingDown else { return }
        notifications.recordReview(id, owners: { notificationDevelopmentOwners })
    }

    func notificationDidSaveHistory() {
        notifications.commitResponses(in: conversations)
    }

    @discardableResult
    func markNotificationRead(_ id: VyronNotificationID) -> Bool {
        guard let item = notificationItems.first(where: { $0.id == id }) else { return false }
        return !item.isUnread || (!isShuttingDown && notifications.markRead([id]))
    }

    func markAllNotificationsRead() {
        guard !isShuttingDown else { return }
        let ids = notificationItems.filter(\.isUnread).map(\.id)
        guard !ids.isEmpty else { return }
        notifications.markRead(ids)
    }
}
