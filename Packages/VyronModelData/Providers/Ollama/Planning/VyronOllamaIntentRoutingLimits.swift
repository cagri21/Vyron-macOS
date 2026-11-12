enum VyronOllamaIntentRoutingLimits {
    static let recentMessageCount = 8
    static let recentConversationBytes = 3_072
    static let promptOverheadTokens = 2_048
    static let outputTokens = 384
    static let compactContextTokens = 16_384
    static let expandedContextTokens = 32_768
    static let maximumResponseBytes = 32_768
    static let maximumResponseContentBytes = 16_000
}
