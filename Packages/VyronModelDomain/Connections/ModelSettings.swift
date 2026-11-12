import Foundation
import VyronLocalization

/// Weight precision belongs to a concrete installed model variant, never a generation option.
public struct ModelSettings: Codable, Equatable, Sendable {
    public var contextTokens: Int?
    public var maxOutputTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var thinking: Bool?
    // The existing Boolean key and public initializer remain compatible with saved connections.
    // Named levels are additive and deliberately do not expand that legacy initializer contract.
    public var thinkingLevel: VyronModelThinkingLevel? = nil
    // Additive optional storage keeps older connection documents and the stable initializer compatible.
    public var responseSpeed: VyronResponseSpeed? = nil

    public init(
        contextTokens: Int? = nil,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        thinking: Bool? = nil
    ) {
        self.contextTokens = contextTokens
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.thinking = thinking
    }

    public func validated() throws -> ModelSettings {
        try validated(
            maximumContext: VyronModelSettingsLimits.defaultMaximumContextTokens,
            maximumOutput: VyronModelSettingsLimits.defaultMaximumOutputTokens
        )
    }

    package func validated(maximumContext: Int, maximumOutput: Int) throws -> ModelSettings {
        let language = VyronResourceLanguage.selection
        let locale = Locale(identifier: language.resolved().rawValue)
        guard thinking == nil || thinkingLevel == nil else {
            throw ModelProviderError.invalidSettings(VyronModelDomainText.settingsThinkingConflict)
        }
        if let contextTokens,
            !(VyronModelSettingsLimits.minimumContextTokens...maximumContext).contains(contextTokens) {
            throw ModelProviderError.invalidSettings(
                VyronModelDomainText.settingsContextRange(
                    VyronModelSettingsLimits.minimumContextTokens.formatted(.number.locale(locale)),
                    maximumContext.formatted(.number.locale(locale)),
                    language: language
                )
            )
        }
        if let maxOutputTokens,
            !(VyronModelSettingsLimits.minimumOutputTokens...maximumOutput).contains(maxOutputTokens) {
            throw ModelProviderError.invalidSettings(
                VyronModelDomainText.settingsOutputRange(
                    VyronModelSettingsLimits.minimumOutputTokens.formatted(.number.locale(locale)),
                    maximumOutput.formatted(.number.locale(locale)),
                    language: language
                )
            )
        }
        if let temperature, !temperature.isFinite || !VyronModelSettingsLimits.temperature.contains(temperature) {
            throw ModelProviderError.invalidSettings(
                VyronModelDomainText.settingsTemperatureRange(
                    VyronModelSettingsLimits.temperature.lowerBound.formatted(.number.locale(locale)),
                    VyronModelSettingsLimits.temperature.upperBound.formatted(.number.locale(locale)),
                    language: language
                )
            )
        }
        if let topP, !topP.isFinite || !VyronModelSettingsLimits.topP.contains(topP) {
            throw ModelProviderError.invalidSettings(
                VyronModelDomainText.settingsTopPRange(
                    VyronModelSettingsLimits.topP.lowerBound.formatted(.number.locale(locale)),
                    VyronModelSettingsLimits.topP.upperBound.formatted(.number.locale(locale)),
                    language: language
                )
            )
        }
        if let contextTokens, let maxOutputTokens, maxOutputTokens >= contextTokens {
            throw ModelProviderError.invalidSettings(VyronModelDomainText.settingsOutputExceedsContext)
        }
        return self
    }
}
