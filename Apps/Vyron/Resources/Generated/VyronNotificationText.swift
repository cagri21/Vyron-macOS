// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronNotificationText {
    static var allNotifications: String {
        VyronResourceBundle.string("notificationAllNotifications", fallback: "All notifications")
    }
    static var approvalRequested: String {
        VyronResourceBundle.string("notificationApprovalRequested", fallback: "A project command needs your approval.")
    }
    static var completed: String {
        VyronResourceBundle.string("notificationCompleted", fallback: "Completed")
    }
    static var emptyDetail: String {
        VyronResourceBundle.string("notificationEmptyDetail", fallback: "Completed tasks, failures, and requests for input will appear here.")
    }
    static var emptyTitle: String {
        VyronResourceBundle.string("notificationEmptyTitle", fallback: "No notifications yet")
    }
    static var failed: String {
        VyronResourceBundle.string("notificationFailed", fallback: "Response failed")
    }
    static var markAllRead: String {
        VyronResourceBundle.string("notificationMarkAllRead", fallback: "Mark all as read")
    }
    static var markRead: String {
        VyronResourceBundle.string("notificationMarkRead", fallback: "Mark as read")
    }
    static var needsAttention: String {
        VyronResourceBundle.string("notificationNeedsAttention", fallback: "Needs input")
    }
    static var older: String {
        VyronResourceBundle.string("notificationOlder", fallback: "Earlier")
    }
    static var `open`: String {
        VyronResourceBundle.string("notificationOpen", fallback: "Open")
    }
    static var openBlocked: String {
        VyronResourceBundle.string("notificationOpenBlocked", fallback: "This update is no longer available.")
    }
    static var openInWindow: String {
        VyronResourceBundle.string("notificationOpenInWindow", fallback: "Open in new window")
    }
    static var pluginApprovalRequested: String {
        VyronResourceBundle.string("notificationPluginApprovalRequested", fallback: "A plugin action needs your review.")
    }
    static var priority: String {
        VyronResourceBundle.string("notificationPriority", fallback: "Priority")
    }
    static var retry: String {
        VyronResourceBundle.string("notificationRetry", fallback: "Retry")
    }
    static var storageError: String {
        VyronResourceBundle.string("notificationStorageError", fallback: "Could not save or load notification read status. Your previous status was preserved.")
    }
    static var title: String {
        VyronResourceBundle.string("notificationTitle", fallback: "Notifications")
    }
    static var today: String {
        VyronResourceBundle.string("notificationToday", fallback: "Today")
    }
    static func unreadCount(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "notificationUnreadCount",
            fallback: "%d unread notifications",
            arguments: [p1]
        )
    }
    static var voiceBusy: String {
        VyronResourceBundle.string("notificationVoiceBusy", fallback: "Finish the voice conversation before opening Plugins.")
    }
    static var working: String {
        VyronResourceBundle.string("notificationWorking", fallback: "Working")
    }
    static var yesterday: String {
        VyronResourceBundle.string("notificationYesterday", fallback: "Yesterday")
    }
}
