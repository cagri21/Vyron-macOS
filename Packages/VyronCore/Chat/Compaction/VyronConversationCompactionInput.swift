public struct VyronConversationCompactionInput: Sendable {
    public let messages: [ChatMessage]
    public let contextByMessageID: [String: String]
    public let previous: VyronConversationCompaction?

    public init(
        messages: [ChatMessage],
        contextByMessageID: [String: String] = [:],
        previous: VyronConversationCompaction? = nil
    ) {
        self.messages = messages
        self.contextByMessageID = contextByMessageID
        self.previous = previous
    }
}
