import Foundation
import VyronLocalization
import VyronModelDomain

enum VyronOllamaDevelopmentBudget {
    static let defaultContextTokens = 32_768

    static func allocation(
        for request: VyronDevelopmentBudgetRequest,
        settings: ModelSettings,
        maximumContext: Int,
        toolBytes: Int
    ) throws -> VyronOllamaDevelopmentAllocation {
        let supported = min(maximumContext, VyronModelSettingsLimits.defaultMaximumContextTokens)
        if let explicit = settings.contextTokens, explicit > supported {
            throw ModelProviderError.invalidSettings(VyronModelDataText.ollamaMaximumContext(String(supported)))
        }
        let output = settings.maxOutputTokens ?? request.configuration.effort.developmentBudget.outputTokens
        guard supported > 0, request.minimumMessageBytes >= 0, request.minimumMessageBytes <= supported,
            toolBytes >= 0, toolBytes <= supported, output > 0, output < supported else {
            throw DevelopmentAgentError.contextBudget
        }
        // Structured thinking may reserve more than Quick's output allowance. Never spend its room on input.
        let outputReserve = max(output, VyronOllamaStructuredOutputBudget.reasoningOutputTokens)
        let overhead = toolBytes + VyronDevelopmentRequestBudget.requestOverheadTokens + outputReserve
        let required = request.minimumMessageBytes + overhead + VyronDevelopmentMessageBudget.maximumToolOutputBytes
        let recommended = ModelCatalog.descriptor(for: request.model.name)?.recommendedContextTokens
            ?? defaultContextTokens
        var context = min(supported, settings.contextTokens ?? recommended)
        if settings.contextTokens == nil {
            if request.configuration.effort == .quick, required <= 16_384 {
                context = min(context, 16_384)
            }
            // Grow only for mandatory input, within the runtime's verified limit. Optional history is compacted.
            while context < required, context < supported {
                context = min(supported, max(context + 1, context * 2))
            }
        }
        let available = context - overhead
        guard available > 0, request.minimumMessageBytes <= available else {
            throw DevelopmentAgentError.contextBudget
        }
        return VyronOllamaDevelopmentAllocation(
            contextTokens: context,
            outputTokens: output,
            messageBudget: VyronDevelopmentMessageBudget(
                workingBytes: max(1, available - VyronDevelopmentMessageBudget.maximumToolOutputBytes),
                maximumBytes: available
            )
        )
    }
}
