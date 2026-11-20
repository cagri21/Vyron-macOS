import Foundation
import VyronModelDomain

extension OllamaClient: VyronDevelopmentAdaptiveBudgetProviding {
    package func developmentBudget(for request: VyronDevelopmentBudgetRequest) async throws -> VyronDevelopmentMessageBudget {
        try await developmentAllocation(for: request).messageBudget
    }

    func developmentAllocation(for request: VyronDevelopmentBudgetRequest) async throws -> VyronOllamaDevelopmentAllocation {
        try Task.checkCancellation()
        let details = try await modelMetadata(for: request.model.name)
        try Task.checkCancellation()
        let tools = try DevelopmentToolDefinition.available(
            mode: request.configuration.mode, externalTools: request.configuration.externalTools
        )
        // Missing metadata does not authorize expanding an automatic context beyond the known default.
        let fallback = ModelCatalog.descriptor(for: request.model.name)?.recommendedContextTokens
            ?? VyronOllamaDevelopmentBudget.defaultContextTokens
        return try VyronOllamaDevelopmentBudget.allocation(
            for: request,
            settings: settings,
            maximumContext: details.maximumContextTokens ?? settings.contextTokens ?? fallback,
            toolBytes: JSONEncoder().encode(tools).count
        )
    }
}
