public struct VyronChatInferenceConfiguration: Sendable {
    public let systemPrompt: String?
    public let effort: AgentEffort
    public let purpose: VyronChatInferencePurpose

    public init(
        systemPrompt: String?,
        effort: AgentEffort,
        purpose: VyronChatInferencePurpose = .conversation
    ) {
        self.systemPrompt = systemPrompt
        self.effort = effort
        self.purpose = purpose
    }
}
