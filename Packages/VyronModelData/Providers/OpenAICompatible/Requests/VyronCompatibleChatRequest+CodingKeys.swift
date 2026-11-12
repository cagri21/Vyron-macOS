import VyronModelDomain

extension VyronCompatibleChatRequest {
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, tools, thinking
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case toolChoice = "tool_choice"
        case reasoningEffort = "reasoning_effort"
    }
}
