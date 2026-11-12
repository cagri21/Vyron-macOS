package enum VyronDevelopmentInference {
    package static func step(
        using provider: any ModelProvider,
        request: VyronDevelopmentInferenceRequest
    ) async throws -> DevelopmentStep {
        if let recoverable = provider as? any VyronDevelopmentInferenceProviding {
            return try await recoverable.developmentInference(request)
        }
        return try await provider.developmentStep(
            model: request.model,
            messages: request.messages,
            effort: request.configuration.effort,
            mode: request.configuration.mode,
            externalTools: request.configuration.externalTools
        )
    }
}
