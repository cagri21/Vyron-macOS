public struct VyronChatInferenceConfiguration: Sendable {
    public let systemPrompt: String?
    public let effort: AgentEffort

    public init(systemPrompt: String?, effort: AgentEffort) {
        self.systemPrompt = systemPrompt
        self.effort = effort
    }
}
