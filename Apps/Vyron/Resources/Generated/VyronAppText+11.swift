// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
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
