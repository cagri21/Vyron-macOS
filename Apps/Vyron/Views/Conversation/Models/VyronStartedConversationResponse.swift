import Foundation

struct VyronStartedConversationResponse {
    let identity: VyronResponseIdentity
    let userMessageID: UUID
    let context: VyronConversationSubmissionContext
}
