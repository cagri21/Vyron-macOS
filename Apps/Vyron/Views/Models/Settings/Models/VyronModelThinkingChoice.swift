import VyronCore

enum VyronModelThinkingChoice: Hashable {
    case automatic
    case enabled
    case disabled
    case level(VyronModelThinkingLevel)

    var title: String {
        switch self {
        case .automatic: VyronAppText.settingsAutomatic
        case .enabled: VyronAppText.settingsThinkingOn
        case .disabled: VyronAppText.settingsThinkingOff
        case .level(.low): VyronAppText.settingsThinkingLow
        case .level(.medium): VyronAppText.settingsThinkingMedium
        case .level(.high): VyronAppText.settingsThinkingHigh
        }
    }

    static func available(for support: VyronModelThinkingSupport) -> [Self] {
        switch support {
        case .boolean:
            return [.automatic, .enabled, .disabled]
        case .levels(let advertised):
            var choices: [Self] = [.automatic]
            if advertised.supportsOn { choices.append(.enabled) }
            if advertised.supportsOff { choices.append(.disabled) }
            for level in VyronModelThinkingLevel.allCases where advertised.levels.contains(level) {
                choices.append(.level(level))
            }
            return choices
        case .unverified, .unsupported, .providerDefaultOnly:
            return [.automatic]
        }
    }
}
