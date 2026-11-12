import Foundation

enum VyronAutomationLabels {
    static func effort(_ value: String) -> String {
        switch value {
        case "auto": VyronAppText.automationAuto
        case "quick": VyronAppText.automationQuick
        case "balanced": VyronAppText.automationBalanced
        case "deep": VyronAppText.automationDeep
        default: value.capitalized
        }
    }

    static func key(_ value: String) -> String {
        VyronAutomationManualKey(rawValue: value)?.title ?? value.capitalized
    }

    static func thermalState(_ value: String) -> String {
        switch value.lowercased() {
        case "nominal": VyronAppText.automationThermalNominal
        case "fair": VyronAppText.automationThermalFair
        case "serious": VyronAppText.automationThermalSerious
        case "critical": VyronAppText.automationThermalCritical
        default: value.capitalized
        }
    }
}
