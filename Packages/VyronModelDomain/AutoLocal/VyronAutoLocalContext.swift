public struct VyronAutoLocalContext: Sendable {
    public let messages: [ChatMessage]
    public let reference: String
    public let requiresTools: Bool
    public let requiresImages: Bool

    public init(messages: [ChatMessage], reference: String, requiresTools: Bool, requiresImages: Bool) {
        self.messages = messages
        self.reference = reference
        self.requiresTools = requiresTools
        self.requiresImages = requiresImages
    }
}
