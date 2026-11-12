import Foundation

struct VyronNotificationResponseID: Codable, Hashable, Sendable {
    let conversationID: UUID
    let responseID: UUID
}
