// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
    static var modelFeaturesSelectModel: String {
        VyronResourceBundle.string("appModelFeaturesSelectModel", fallback: "Choose a model to check its features.")
    }
    static var modelFeaturesThinking: String {
        VyronResourceBundle.string("appModelFeaturesThinking", fallback: "Thinking controls")
    }
    static var modelFeaturesThinkingConnection: String {
        VyronResourceBundle.string("appModelFeaturesThinkingConnection", fallback: "This connection cannot change the model’s thinking settings in Vyron.")
    }
    static var modelFeaturesThinkingLevelsUnsupported: String {
        VyronResourceBundle.string("appModelFeaturesThinkingLevelsUnsupported", fallback: "This model reports thinking options Vyron does not support. The model’s default remains in use.")
    }
    static var modelFeaturesTitle: String {
        VyronResourceBundle.string("appModelFeaturesTitle", fallback: "Features for this model")
    }
    static var modelFeaturesToolsUnsupported: String {
        VyronResourceBundle.string("appModelFeaturesToolsUnsupported", fallback: "Native tool calling could not be verified for this model. Chat remains available.")
    }
    static var modelFeaturesUnavailable: String {
        VyronResourceBundle.string("appModelFeaturesUnavailable", fallback: "Unavailable")
    }
    static func modelFeaturesUnavailableList(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appModelFeaturesUnavailableList",
            fallback: "Unavailable: %@",
            arguments: [p1]
        )
    }
    static var modelFeaturesUnverified: String {
        VyronResourceBundle.string("appModelFeaturesUnverified", fallback: "Not verified")
    }
    static func modelFeaturesUnverifiedList(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appModelFeaturesUnverifiedList",
            fallback: "Not verified: %@",
            arguments: [p1]
        )
    }
    static var settingsActiveConnection: String {
        VyronResourceBundle.string("appSettingsActiveConnection", fallback: "Active connection")
    }
    static var settingsAddClaude: String {
        VyronResourceBundle.string("appSettingsAddClaude", fallback: "Add Claude")
    }
    static var settingsAddDeepSeek: String {
        VyronResourceBundle.string("appSettingsAddDeepSeek", fallback: "Add DeepSeek")
    }
    static var settingsAddLocalModel: String {
        VyronResourceBundle.string("appSettingsAddLocalModel", fallback: "Add another local model")
    }
    static var settingsAddOpenAI: String {
        VyronResourceBundle.string("appSettingsAddOpenAI", fallback: "Add OpenAI")
    }
    static var settingsAddServer: String {
        VyronResourceBundle.string("appSettingsAddServer", fallback: "Add server URL")
    }
    static var settingsAgentToolsAdvertised: String {
        VyronResourceBundle.string("appSettingsAgentToolsAdvertised", fallback: "Agent tools advertised")
    }
    static var settingsAllAvailable: String {
        VyronResourceBundle.string("appSettingsAllAvailable", fallback: "All available")
    }
    static var settingsApply: String {
        VyronResourceBundle.string("appSettingsApply", fallback: "Apply settings")
    }
    static var settingsAutomatic: String {
        VyronResourceBundle.string("appSettingsAutomatic", fallback: "Automatic")
    }
    static func settingsAutomaticContextTokens(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsAutomaticContextTokens",
            fallback: "Automatic (%@)",
            arguments: [p1]
        )
    }
    static var settingsAutomaticDescription: String {
        VyronResourceBundle.string("appSettingsAutomaticDescription", fallback: "Chooses a compatible installed coding model. The large manual-only option and the small helper stay out of coding Auto.")
    }
    static var settingsAutomaticSelection: String {
        VyronResourceBundle.string("appSettingsAutomaticSelection", fallback: "Automatic selection")
    }
    static var settingsAvailableModel: String {
        VyronResourceBundle.string("appSettingsAvailableModel", fallback: "Available model")
    }
    static func settingsAvailableVariantCount(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "appSettingsAvailableVariantCount",
            fallback: "%d available variants",
            arguments: [p1]
        )
    }
    static var settingsBuiltinDetail: String {
        VyronResourceBundle.string("appSettingsBuiltinDetail", fallback: "Built-in Ollama · local inference")
    }
    static var settingsCancel: String {
        VyronResourceBundle.string("appSettingsCancel", fallback: "Cancel")
    }
    static var settingsCancelImport: String {
        VyronResourceBundle.string("appSettingsCancelImport", fallback: "Cancel import")
    }
    static var settingsChangePrecision: String {
        VyronResourceBundle.string("appSettingsChangePrecision", fallback: "Change precision…")
    }
    static func settingsChangePrecisionTitle(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsChangePrecisionTitle",
            fallback: "Change precision for %@",
            arguments: [p1]
        )
    }
    static func settingsChangingPrecision(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsChangingPrecision",
            fallback: "Switching to %@…",
            arguments: [p1]
        )
    }
    static var settingsChatHelper: String {
        VyronResourceBundle.string("appSettingsChatHelper", fallback: "Chat helper")
    }
    static var settingsCheckAgain: String {
        VyronResourceBundle.string("appSettingsCheckAgain", fallback: "Check again")
    }
    static var settingsCheckingConnection: String {
        VyronResourceBundle.string("appSettingsCheckingConnection", fallback: "Checking model connection…")
    }
    static var settingsCheckingFiles: String {
        VyronResourceBundle.string("appSettingsCheckingFiles", fallback: "Checking downloaded files…")
    }
}
