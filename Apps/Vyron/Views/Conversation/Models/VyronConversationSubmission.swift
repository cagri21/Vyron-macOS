import VyronCore

struct VyronConversationSubmission {
    let draft: VyronConversationSubmissionDraft
    let compaction: VyronConversationCompactionSubmission?
    let compactedMemory: ChatMessage?
    let queuedMessage: VyronQueuedMessage?
}
