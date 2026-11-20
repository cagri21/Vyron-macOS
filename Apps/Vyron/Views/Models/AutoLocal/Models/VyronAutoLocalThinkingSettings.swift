import VyronModelDomain

enum VyronAutoLocalThinkingSettings {
    static func applying(
        to settings: ModelSettings,
        support: VyronModelThinkingSupport,
        effort: AgentEffort
    ) -> ModelSettings {
        guard settings.thinking == nil, settings.thinkingLevel == nil, effort != .automatic else { return settings }
        var result = settings
        switch support {
        case .boolean:
            result.thinking = effort != .quick
        case .levels(let controls):
            let level: VyronModelThinkingLevel
            switch effort {
            case .quick: level = .low
            case .balanced: level = .medium
            case .deep, .extraHigh, .maximum, .ultra: level = .high
            case .automatic: return settings
            }
            if controls.levels.contains(level) { result.thinkingLevel = level }
        case .unverified, .unsupported, .providerDefaultOnly:
            break
        }
        return result
    }
}
