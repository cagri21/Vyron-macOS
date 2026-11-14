// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
    static func settingsClaudeOutputLimit(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsClaudeOutputLimit",
            fallback: "This model supports up to %@ output tokens.",
            arguments: [p1]
        )
    }
    static var settingsClaudePrivacy: String {
        VyronResourceBundle.string("appSettingsClaudePrivacy", fallback: "The server above receives messages and project excerpts sent through this connection. Your key is stored in macOS Keychain.")
    }
    static var settingsCloseConnection: String {
        VyronResourceBundle.string("appSettingsCloseConnection", fallback: "Close connection editor")
    }
    static var settingsCloseModels: String {
        VyronResourceBundle.string("appSettingsCloseModels", fallback: "Close model manager")
    }
    static var settingsCodingOptions: String {
        VyronResourceBundle.string("appSettingsCodingOptions", fallback: "Coding options")
    }
    static var settingsCompatibleAPI: String {
        VyronResourceBundle.string("appSettingsCompatibleAPI", fallback: "OpenAI-compatible API")
    }
    static var settingsCompleteSourceURL: String {
        VyronResourceBundle.string("appSettingsCompleteSourceURL", fallback: "Enter a complete model source URL.")
    }
    static var settingsConnectionName: String {
        VyronResourceBundle.string("appSettingsConnectionName", fallback: "Connection name")
    }
    static var settingsConnections: String {
        VyronResourceBundle.string("appSettingsConnections", fallback: "Connections")
    }
    static var settingsConnectionSavedUnavailable: String {
        VyronResourceBundle.string("appSettingsConnectionSavedUnavailable", fallback: "The connection was saved. Select it when the server is available.")
    }
    static var settingsContextBudget: String {
        VyronResourceBundle.string("appSettingsContextBudget", fallback: "Context budget (tokens)")
    }
    static var settingsContextTokens: String {
        VyronResourceBundle.string("appSettingsContextTokens", fallback: "Context tokens")
    }
    static func settingsDecimalRequired(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsDecimalRequired",
            fallback: "%@ must be a number, such as 0.7.",
            arguments: [p1]
        )
    }
    static var settingsDeepSeekAPIKey: String {
        VyronResourceBundle.string("appSettingsDeepSeekAPIKey", fallback: "DeepSeek API key")
    }
    static var settingsDeepSeekPrivacy: String {
        VyronResourceBundle.string("appSettingsDeepSeekPrivacy", fallback: "Your prompts and selected project context are sent to DeepSeek. Your API key is stored in macOS Keychain.")
    }
    static var settingsDefaultsHint: String {
        VyronResourceBundle.string("appSettingsDefaultsHint", fallback: "Leave a field blank for Vyron’s automatic defaults. Context and response space depend on the selected model.")
    }
    static var settingsDevstralMemory: String {
        VyronResourceBundle.string("appSettingsDevstralMemory", fallback: "15 GB weights; a smaller download among the coding options.")
    }
    static var settingsDevstralSummary: String {
        VyronResourceBundle.string("appSettingsDevstralSummary", fallback: "Software engineering model for repository exploration and editing.")
    }
    static var settingsDiscoverModels: String {
        VyronResourceBundle.string("appSettingsDiscoverModels", fallback: "Discover models")
    }
    static var settingsDownload: String {
        VyronResourceBundle.string("appSettingsDownload", fallback: "Download")
    }
    static var settingsDownloadByURL: String {
        VyronResourceBundle.string("appSettingsDownloadByURL", fallback: "Download a model by URL")
    }
    static var settingsDownloadImport: String {
        VyronResourceBundle.string("appSettingsDownloadImport", fallback: "Download & import")
    }
    static var settingsDownloadingModelFiles: String {
        VyronResourceBundle.string("appSettingsDownloadingModelFiles", fallback: "Downloading model files…")
    }
    static func settingsDownloadingNotice(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsDownloadingNotice",
            fallback: "Downloading %@. Pause its download before starting another.",
            arguments: [p1]
        )
    }
    static func settingsDownloadProgress(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "appSettingsDownloadProgress",
            fallback: "%@ of %@",
            arguments: [p1, p2]
        )
    }
    static func settingsDownloadSize(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsDownloadSize",
            fallback: "~%@ GB download",
            arguments: [p1]
        )
    }
    static var settingsDownloadVariant: String {
        VyronResourceBundle.string("appSettingsDownloadVariant", fallback: "Download variant")
    }
    static func settingsEditConnection(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsEditConnection",
            fallback: "Edit %@",
            arguments: [p1]
        )
    }
    static var settingsExactModelID: String {
        VyronResourceBundle.string("appSettingsExactModelID", fallback: "Exact model ID from your server")
    }
    static var settingsFindingModelFiles: String {
        VyronResourceBundle.string("appSettingsFindingModelFiles", fallback: "Finding model files…")
    }
    static var settingsFindingVariants: String {
        VyronResourceBundle.string("appSettingsFindingVariants", fallback: "Finding published variants…")
    }
    static var settingsFindVariants: String {
        VyronResourceBundle.string("appSettingsFindVariants", fallback: "Find variants")
    }
    static var settingsFinishingSetup: String {
        VyronResourceBundle.string("appSettingsFinishingSetup", fallback: "Finishing local setup…")
    }
    static func settingsFreeStorage(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsFreeStorage",
            fallback: "%@ free",
            arguments: [p1]
        )
    }
    static var settingsGenericModel: String {
        VyronResourceBundle.string("appSettingsGenericModel", fallback: "a model")
    }
}
