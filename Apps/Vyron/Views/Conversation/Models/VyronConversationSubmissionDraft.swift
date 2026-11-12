import VyronCore

struct VyronConversationSubmissionDraft {
    let enteredPrompt: String
    let prompt: String
    let images: [VyronImageAttachment]
    let folderContext: String
}
