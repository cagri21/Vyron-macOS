import Foundation
import VyronLocalization
import VyronModelDomain

extension ModelConnectionProfile {
    public var publishedOutputTokenLimit: Int? {
        let model = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .anthropic, VyronClaudeModelBudget.hasPublishedLimits(for: model) {
            return VyronClaudeModelBudget.maximumOutputTokens(for: model)
        }
        if let budget = VyronDeepSeekModelBudget.published(for: self, model: model) {
            return budget.maximumOutputTokens
        }
        return VyronHostedCompatibleOutputLimit.published(for: self, model: model)
    }

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
            result.settings = try result.validatedCompatibleSettings(for: result.selectedModel)
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

    func validatedCompatibleSettings(for model: String) throws -> ModelSettings {
        if let maximum = VyronHostedCompatibleOutputLimit.published(for: self, model: model) {
            // A formerly accepted override can stay in a saved profile. Inference still respects the model cap.
            return try settings.validated(maximumOutput: maximum, preservesLegacyOutputRange: true)
        }
        return try settings.validated()
    }

    public func validatedForEditing() throws -> ModelConnectionProfile {
        let profile = try validated()
        if let limit = profile.publishedOutputTokenLimit, let output = profile.settings.maxOutputTokens,
            output > limit {
            _ = try profile.settings.validated(maximumOutput: limit)
        }
        return profile
    }

    public func makeProvider(
        apiKey: String? = nil,
        usageHandler: (@Sendable (VyronOpenAIUsageEvent) async -> Void)? = nil
    ) throws -> any ModelProvider {
        try VyronModelProviderFactory.makeProvider(for: self, apiKey: apiKey, usageHandler: usageHandler)
    }
}
