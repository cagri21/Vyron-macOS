import VyronCore

struct VyronSideChatTurn: Sendable {
    let response: VyronSideChatResponse
    let messages: [ChatMessage]
}
