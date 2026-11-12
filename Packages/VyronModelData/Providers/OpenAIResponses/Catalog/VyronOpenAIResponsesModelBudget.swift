import VyronModelDomain

enum VyronOpenAIResponsesModelBudget {
    private static let standardContextTokens = 32_768
    // OpenAI documents a 1,050,000-token context for these models. Use Vyron's supported working limit by default.
    private static let expandedContextTokens = 131_072
    private static let expandedDevelopmentMessages = VyronDevelopmentMessageBudget(
        workingBytes: 98_304,
        maximumBytes: 131_072
    )

    static func contextTokens(for model: String, override: Int?) -> Int {
        override ?? (usesExpandedBudget(for: model) ? expandedContextTokens : standardContextTokens)
    }

    static func developmentMessages(for model: String) -> VyronDevelopmentMessageBudget {
        usesExpandedBudget(for: model) ? expandedDevelopmentMessages : .standard
    }

    private static func usesExpandedBudget(for model: String) -> Bool {
        switch VyronOpenAIResponsesRoute.modelFamily(for: model) {
        case .gpt61Sol, .gpt6Sol, .gpt6Astra: true
        case .gpt6Luna, .gpt61Terra, nil: false
        }
    }
}
