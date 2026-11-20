import VyronModelDomain

enum VyronDevelopmentBudgetResolver {
    static func resolve(
        using provider: any ModelProvider,
        request: VyronDevelopmentBudgetRequest
    ) async throws -> VyronDevelopmentMessageBudget {
        if let adaptive = provider as? any VyronDevelopmentAdaptiveBudgetProviding {
            let budget = try await adaptive.developmentBudget(for: request)
            try Task.checkCancellation()
            return budget
        }
        return (provider as? any VyronDevelopmentMessageBudgetProviding)?
            .developmentMessageBudget(for: request.model.name) ?? .standard
    }
}
