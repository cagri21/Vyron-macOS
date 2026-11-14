import Foundation
import VyronCore
import VyronDevelopment

struct Conversation: Identifiable, Codable {
    var id: UUID
    var title: String
    var updatedAt: Date
    var messages: [ChatMessage]
    /// The actual source folder used by this chat's file and command tools.
    var workspacePath: String?
    /// Stable sidebar owner. Absent in older history, which used one folder per project.
    var projectPath: String?
    var contextByMessageID: [String: String]?
    var changesByResponseID: [String: [VyronDevelopmentResponseChanges]]?
    var mode: String?
    var queuedMessages: [VyronQueuedMessage]?
    /// Optional inference memory; the complete visible transcript remains in messages.
    var compaction: VyronConversationCompaction?
    /// Missing in earlier history; a manual unread marker survives reopening the app.
    var isUnread: Bool?

    var sidebarProjectPath: String? { projectPath ?? workspacePath }

    init(title: String, workspacePath: String?) {
        id = UUID()
        self.title = title
        updatedAt = Date()
        messages = []
        self.workspacePath = workspacePath
    }
}
