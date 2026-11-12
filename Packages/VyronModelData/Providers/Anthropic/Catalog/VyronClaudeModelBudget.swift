import Foundation
import VyronLocalization
import VyronModelDomain

public enum VyronClaudeModelBudget {
    private static let standardContext = 32_768
    private static let standardOutput = 32_768
    private static let expandedContext = 1_000_000
    private static let expandedOutput = 128_000
    private static let legacyContext = 200_000
    private static let legacyOutput = 64_000

    // Anthropic's context-window and output-limit tables. Retired models can still exist in saved profiles.
    private static let expandedFamilies: Set<String> = [
        "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
        "claude-sonnet-5-5", "claude-sonnet-5", "claude-sonnet-4-6", "claude-haiku-5-5",
        "claude-fable-5-2", "claude-fable-5-1", "claude-fable-5",
        "claude-mythos-5-2", "claude-mythos-5-1", "claude-mythos-5", "claude-mythos-preview"
    ]
    private static let legacyFamilies: Set<String> = ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"]

    static let developmentMessages = VyronDevelopmentMessageBudget(workingBytes: 98_304, maximumBytes: 131_072)

    public static func contextTokens(for model: String) -> Int {
        let family = family(for: model)
        if expandedFamilies.contains(family) { return expandedContext }
        if legacyFamilies.contains(family) { return legacyContext }
        return standardContext
    }

    public static func maximumOutputTokens(for model: String) -> Int {
        let family = family(for: model)
        if expandedFamilies.contains(family) { return expandedOutput }
        if legacyFamilies.contains(family) { return legacyOutput }
        return standardOutput
    }

    public static func hasPublishedLimits(for model: String) -> Bool {
        let family = family(for: model)
        return expandedFamilies.contains(family) || legacyFamilies.contains(family)
    }

    static func validated(_ settings: ModelSettings, for model: String) throws -> ModelSettings {
        guard settings.temperature == nil, settings.topP == nil,
            settings.thinking == nil, settings.thinkingLevel == nil
        else {
            throw ModelProviderError.invalidSettings(VyronModelDataText.claudeManagedControls)
        }
        let known = hasPublishedLimits(for: model)
        let validated = try settings.validated(
            maximumContext: known ? contextTokens(for: model) : expandedContext,
            maximumOutput: known ? maximumOutputTokens(for: model) : expandedOutput
        )
        if let output = validated.maxOutputTokens, output >= (validated.contextTokens ?? contextTokens(for: model)) {
            throw ModelProviderError.invalidSettings(VyronModelDomainText.settingsOutputExceedsContext)
        }
        return validated
    }

    private static func family(for model: String) -> String {
        guard let separator = model.lastIndex(of: "-") else { return model }
        let snapshot = model[model.index(after: separator)...].utf8
        guard snapshot.count == 8, snapshot.allSatisfy({ (48...57).contains($0) }) else { return model }
        return String(model[..<separator])
    }
}
