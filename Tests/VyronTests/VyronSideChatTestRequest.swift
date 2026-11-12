import VyronCore

struct VyronSideChatTestRequest: Sendable {
    let model: String
    let messages: [ChatMessage]
    let systemPrompt: String?
}
