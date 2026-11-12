import VyronCore

struct VyronConversationSubmissionContext {
    let history: [ChatMessage]
    let previousContext: [String: String]
    let attachments: VyronConversationSubmissionAttachments
    let compaction: VyronConversationCompaction?
}
