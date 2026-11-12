import Foundation

struct VyronSideChatResponse: Equatable, Sendable {
    let generationID: UUID
    let conversationID: UUID
    let messageID: UUID
}
