package struct VyronDevelopmentInferenceRequest: Sendable {
    package let model: String
    package let messages: [DevelopmentMessage]
    package let configuration: VyronDevelopmentInferenceConfiguration

    package init(model: String, messages: [DevelopmentMessage], configuration: VyronDevelopmentInferenceConfiguration) {
        self.model = model
        self.messages = messages
        self.configuration = configuration
    }
}
