import VyronModelDomain

extension OllamaClient {
    func chatGeneration(
        for model: LocalModel,
        configuration: VyronChatInferenceConfiguration,
        budget: VyronOllamaStructuredOutputBudget
    ) async throws -> VyronOllamaChatGeneration {
        let thinking: VyronOllamaThinkingValue?
        let outputTokens: Int
        let format: VyronOllamaChatFormat?
        switch configuration.purpose {
        case .conversation:
            thinking = try await structuredThinkingOption(for: model, effort: configuration.effort)
            outputTokens = try budget.resolved(reasoningMayRun: false, maximumOutputTokens: settings.maxOutputTokens)
            format = nil
        case .modelAssessment:
            // Classification needs visible JSON. Disable native reasoning only when the model permits it;
            // mandatory reasoning uses the same bounded headroom as other structured Ollama responses.
            let support = try await thinkingControlSupport(for: model)
            switch support {
            case .boolean:
                thinking = .toggle(.disabled)
            case .levels(let controls) where controls.supportsOff:
                thinking = .toggle(.disabled)
            case .levels, .providerDefaultOnly, .unsupported, .unverified:
                thinking = try await structuredThinkingOption(for: model, effort: configuration.effort)
            }
            outputTokens = try structuredOutputTokens(model: model, thinking: thinking, budget: budget)
            format = .json
        }
        return VyronOllamaChatGeneration(
            think: thinking,
            format: format,
            options: VyronOllamaChatOptions(
                num_ctx: budget.contextTokens,
                num_predict: outputTokens,
                temperature: settings.temperature ?? 0.3,
                top_p: settings.topP
            )
        )
    }
}
