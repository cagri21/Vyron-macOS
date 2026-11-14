// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
    static var settingsRecommended: String {
        VyronResourceBundle.string("appSettingsRecommended", fallback: "Recommended to try")
    }
    static var settingsRefresh: String {
        VyronResourceBundle.string("appSettingsRefresh", fallback: "Refresh")
    }
    static var settingsRemoteServer: String {
        VyronResourceBundle.string("appSettingsRemoteServer", fallback: "Remote server")
    }
    static func settingsRemoveConnection(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsRemoveConnection",
            fallback: "Remove %@",
            arguments: [p1]
        )
    }
    static func settingsRemovingPreviousVariant(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsRemovingPreviousVariant",
            fallback: "Removing %@…",
            arguments: [p1]
        )
    }
    static var settingsRequestBudgetHint: String {
        VyronResourceBundle.string("appSettingsRequestBudgetHint", fallback: "This limits Vyron’s request budget. The server determines its model’s actual context capacity.")
    }
    static var settingsResume: String {
        VyronResourceBundle.string("appSettingsResume", fallback: "Resume")
    }
    static var settingsSaveTestHint: String {
        VyronResourceBundle.string("appSettingsSaveTestHint", fallback: "Saving tests a short response before storing this connection.")
    }
    static var settingsSaveUse: String {
        VyronResourceBundle.string("appSettingsSaveUse", fallback: "Save & use")
    }
    static var settingsSelected: String {
        VyronResourceBundle.string("appSettingsSelected", fallback: "Selected")
    }
    static func settingsSelectedUnavailable(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsSelectedUnavailable",
            fallback: "Your selected model, %@, is unavailable from this connection. Choose an available model or check its server; manual selection never falls back silently.",
            arguments: [p1]
        )
    }
    static var settingsServerPrivacy: String {
        VyronResourceBundle.string("appSettingsServerPrivacy", fallback: "The selected server receives messages and project excerpts. A local server may forward them to a hosted model. Keys are stored in macOS Keychain.")
    }
    static var settingsServerType: String {
        VyronResourceBundle.string("appSettingsServerType", fallback: "Server type")
    }
    static var settingsServerURL: String {
        VyronResourceBundle.string("appSettingsServerURL", fallback: "Server URL")
    }
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
    static var settingsSwitchVariant: String {
        VyronResourceBundle.string("appSettingsSwitchVariant", fallback: "Switch variant")
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
}
