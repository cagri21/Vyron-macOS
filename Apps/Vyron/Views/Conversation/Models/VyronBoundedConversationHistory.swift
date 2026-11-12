import VyronCore

struct VyronBoundedConversationHistory {
    var messages: [ChatMessage]
    let omittedOlderMessages: Bool
}
