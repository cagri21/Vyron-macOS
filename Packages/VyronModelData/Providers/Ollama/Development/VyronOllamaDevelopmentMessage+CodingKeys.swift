extension VyronOllamaDevelopmentMessage {
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
        case toolCallID = "tool_call_id"
        case images
    }
}
