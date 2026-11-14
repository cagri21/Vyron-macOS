import Foundation
import VyronModelDomain

struct VyronConversationTranscriptRow: Identifiable {
    let message: ChatMessage
    let clarificationAnswers: [VyronClarificationAnswer]

    var id: UUID { message.id }
}
