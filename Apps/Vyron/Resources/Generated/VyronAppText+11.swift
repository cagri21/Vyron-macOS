// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
    static var settingsThinkingMedium: String {
        VyronResourceBundle.string("appSettingsThinkingMedium", fallback: "Medium")
    }
    static var settingsThinkingOff: String {
        VyronResourceBundle.string("appSettingsThinkingOff", fallback: "Off, when supported")
    }
    static var settingsThinkingOn: String {
        VyronResourceBundle.string("appSettingsThinkingOn", fallback: "On, when supported")
    }
    static var settingsThinkingSelectionUnavailable: String {
        VyronResourceBundle.string("appSettingsThinkingSelectionUnavailable", fallback: "Choose an available thinking option for this model.")
    }
    static var settingsThisMac: String {
        VyronResourceBundle.string("appSettingsThisMac", fallback: "On this Mac")
    }
    static var settingsTopP: String {
        VyronResourceBundle.string("appSettingsTopP", fallback: "Top P")
    }
    static var settingsUse: String {
        VyronResourceBundle.string("appSettingsUse", fallback: "Use")
    }
    static var settingsUseAuto: String {
        VyronResourceBundle.string("appSettingsUseAuto", fallback: "Use Auto")
    }
    static var settingsUseDefaults: String {
        VyronResourceBundle.string("appSettingsUseDefaults", fallback: "Use defaults")
    }
    static var settingsUseForChat: String {
        VyronResourceBundle.string("appSettingsUseForChat", fallback: "Use for chat")
    }
    static var settingsUseModel: String {
        VyronResourceBundle.string("appSettingsUseModel", fallback: "Use model")
    }
    static var settingsVariant: String {
        VyronResourceBundle.string("appSettingsVariant", fallback: "Variant")
    }
    static var settingsWeightsExceedMemory: String {
        VyronResourceBundle.string("appSettingsWeightsExceedMemory", fallback: "These weights exceed this Mac’s physical memory.")
    }
    static func settingsWeightSize(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsWeightSize",
            fallback: "%@ weights",
            arguments: [p1]
        )
    }
}
