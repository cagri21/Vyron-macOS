import Foundation
import VyronLocalization
import VyronModelDomain

extension ModelConnectionProfile {
    public func validated() throws -> ModelConnectionProfile {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty, result.name.count <= VyronModelConnectionLimits.maximumNameCharacters else {
            throw ModelProviderError.invalidSettings(
                VyronModelDataText.connectionNameLimit(VyronModelConnectionLimits.maximumNameCharacters)
            )
        }
        result.endpoint = try ModelEndpoint.validated(endpoint, kind: kind).absoluteString
        result.selectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.selectedModel.isEmpty { try ModelEndpoint.validateModelID(result.selectedModel) }
        if kind == .anthropic {
            result.settings = try VyronClaudeModelBudget.validated(settings, for: result.selectedModel)
        } else if let limits = VyronDeepSeekModelBudget.published(for: result) {
            result.settings = try settings.validated(
                maximumContext: limits.contextTokens,
                maximumOutput: limits.maximumOutputTokens
            )
        } else {
            result.settings = try settings.validated()
        }
        if kind == .openAICompatible, settings.thinking != nil || settings.thinkingLevel != nil {
            let supportsDeepSeekToggle =
                VyronDeepSeekRoute.matches(result)
                && VyronDeepSeekRoute.thinkingSupport(for: result.selectedModel) == .boolean
                && settings.thinkingLevel == nil
            guard supportsDeepSeekToggle else {
                throw ModelProviderError.invalidSettings(
                    VyronModelDataText.connectionThinkingUnavailable
                )
            }
        }
        return result
    }

    public func makeProvider(
        apiKey: String? = nil,
        usageHandler: (@Sendable (VyronOpenAIUsageEvent) async -> Void)? = nil
    ) throws -> any ModelProvider {
        try VyronModelProviderFactory.makeProvider(for: self, apiKey: apiKey, usageHandler: usageHandler)
    }
}
