import Foundation
@testable import VyronCore

struct VyronScheduledProviderChatRequest: Sendable {
    let model: String
    let messages: [ChatMessage]
    let systemPrompt: String?
}
