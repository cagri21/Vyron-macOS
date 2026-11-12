public struct VyronChatInferenceRequest: Sendable {
    public let model: String
    public let messages: [ChatMessage]
    public let configuration: VyronChatInferenceConfiguration

    public init(model: String, messages: [ChatMessage], configuration: VyronChatInferenceConfiguration) {
        self.model = model
        self.messages = messages
        self.configuration = configuration
    }
}
