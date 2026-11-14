import Foundation
import VyronCore

struct VyronModelSettingsDraft: Equatable {
    var budget: VyronModelBudgetDraft
    var sampling: VyronModelSamplingDraft
    var thinking: VyronModelThinkingChoice
    var responseSpeed: VyronResponseSpeed?

    init(_ settings: ModelSettings) {
        budget = VyronModelBudgetDraft(settings)
        sampling = VyronModelSamplingDraft(settings)
        responseSpeed = settings.responseSpeed
        if let level = settings.thinkingLevel {
            thinking = .level(level)
        } else {
            thinking = settings.thinking.map { $0 ? .enabled : .disabled } ?? .automatic
        }
    }

    func settings(thinkingSupport: VyronModelThinkingSupport, includesSampling: Bool = true) throws -> ModelSettings {
        guard
            thinkingSupport == .unverified
                || VyronModelThinkingChoice.available(for: thinkingSupport).contains(thinking)
        else { throw VyronModelSettingsInputError(message: VyronAppText.settingsThinkingSelectionUnavailable) }
        var value = try ModelSettings(
            contextTokens: integer(budget.contextTokens, label: VyronAppText.settingsContextTokens),
            maxOutputTokens: integer(budget.maxOutputTokens, label: VyronAppText.settingsMaxResponseTokens),
            temperature: includesSampling
                ? decimal(sampling.temperature, label: VyronAppText.settingsTemperature) : nil,
            topP: includesSampling ? decimal(sampling.topP, label: VyronAppText.settingsTopP) : nil,
            thinking: thinking == .enabled ? true : thinking == .disabled ? false : nil
        )
        if case .level(let level) = thinking { value.thinkingLevel = level }
        value.responseSpeed = responseSpeed
        value.ollamaDevelopmentTimeoutSeconds = try integer(
            budget.ollamaDevelopmentTimeoutSeconds,
            label: VyronAppText.settingsOllamaDevelopmentTimeout
        )
        return value
    }

    mutating func reconcileThinking(with support: VyronModelThinkingSupport) {
        guard support != .unverified else { return }
        if !VyronModelThinkingChoice.available(for: support).contains(thinking) {
            thinking = .automatic
        }
    }

    private func integer(_ text: String, label: String) throws -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let result = Int(value) else {
            throw VyronModelSettingsInputError(message: VyronAppText.settingsIntegerRequired(label))
        }
        return result
    }

    private func decimal(_ text: String, label: String) throws -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let result = Double(value), result.isFinite else {
            throw VyronModelSettingsInputError(message: VyronAppText.settingsDecimalRequired(label))
        }
        return result
    }
}
