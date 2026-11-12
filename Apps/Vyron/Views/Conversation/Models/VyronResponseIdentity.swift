import Foundation

struct VyronResponseIdentity: Equatable, Sendable {
    let generationID: UUID
    let conversationID: UUID
    let messageID: UUID
}
