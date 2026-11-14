// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
    static var settingsSourceHint: String {
        VyronResourceBundle.string("appSettingsSourceHint", fallback: "Paste an Ollama library page, a public Hugging Face GGUF repository, or a direct .gguf link.")
    }
    static var settingsSourceURL: String {
        VyronResourceBundle.string("appSettingsSourceURL", fallback: "Model source URL")
    }
    static var settingsStartEngine: String {
        VyronResourceBundle.string("appSettingsStartEngine", fallback: "Start engine")
    }
    static var settingsStartEngineHint: String {
        VyronResourceBundle.string("appSettingsStartEngineHint", fallback: "Start the local engine to see installed models and download weights.")
    }
    static func settingsSuggestedContext(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "appSettingsSuggestedContext",
            fallback: "%dK suggested context",
            arguments: [p1]
        )
    }
    static var settingsTaskBlocksModels: String {
        VyronResourceBundle.string("appSettingsTaskBlocksModels", fallback: "Finish or stop the current task to change models or start a download.")
    }
    static var settingsTemperature: String {
        VyronResourceBundle.string("appSettingsTemperature", fallback: "Temperature")
    }
    static var settingsTestResponse: String {
        VyronResourceBundle.string("appSettingsTestResponse", fallback: "Test response")
    }
    static var settingsThinking: String {
        VyronResourceBundle.string("appSettingsThinking", fallback: "Thinking")
    }
    static var settingsThinkingHigh: String {
        VyronResourceBundle.string("appSettingsThinkingHigh", fallback: "High")
    }
    static var settingsThinkingHint: String {
        VyronResourceBundle.string("appSettingsThinkingHint", fallback: "Automatic uses the model’s default. Higher levels can take longer; task effort controls separate task budgets.")
    }
    static var settingsThinkingLow: String {
        VyronResourceBundle.string("appSettingsThinkingLow", fallback: "Low")
    }
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
