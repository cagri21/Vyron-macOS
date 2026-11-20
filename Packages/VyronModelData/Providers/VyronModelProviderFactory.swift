import VyronModelDomain

public enum VyronModelProviderFactory {
    package static func changesTransport(for profile: ModelConnectionProfile, selecting model: String) -> Bool {
        var updated = profile
        updated.selectedModel = model
        return VyronOpenAIResponsesRoute.matches(profile) != VyronOpenAIResponsesRoute.matches(updated)
    }

    public static func makeProvider(
        for profile: ModelConnectionProfile,
        apiKey: String? = nil,
        usageHandler: (@Sendable (VyronOpenAIUsageEvent) async -> Void)? = nil
    ) throws -> any ModelProvider {
        switch profile.kind {
        case .ollama:
            return try OllamaClient(connection: profile, apiKey: apiKey)
        case .anthropic:
            return try VyronAnthropicClient(connection: profile, apiKey: apiKey)
        case .openAICompatible:
            let validated = try profile.validated()
            if VyronOpenAIResponsesRoute.matches(validated) {
                return try VyronOpenAIResponsesClient(
                    connection: validated,
                    apiKey: apiKey,
                    usageHandler: usageHandler
                )
            }
            return try OpenAICompatibleClient(connection: validated, apiKey: apiKey, usageHandler: usageHandler)
        }
    }
}
