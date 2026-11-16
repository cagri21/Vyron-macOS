// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
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
    static var settingsGeminiAPIKey: String {
        VyronResourceBundle.string("appSettingsGeminiAPIKey", fallback: "Gemini API key")
    }
    static var settingsGeminiPrivacy: String {
        VyronResourceBundle.string("appSettingsGeminiPrivacy", fallback: "Your prompts and selected project context are sent to Google. Your API key is stored in macOS Keychain.")
    }
    static var settingsGenericModel: String {
        VyronResourceBundle.string("appSettingsGenericModel", fallback: "a model")
    }
    static var settingsGetOllama: String {
        VyronResourceBundle.string("appSettingsGetOllama", fallback: "Get Ollama ↗")
    }
    static var settingsHostedOutputLimitUnverified: String {
        VyronResourceBundle.string("appSettingsHostedOutputLimitUnverified", fallback: "Vyron has no verified output limit for this model.")
    }
    static func settingsImportingNotice(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsImportingNotice",
            fallback: "Importing %@. Cancel the import before starting another; canceled file imports restart from the beginning.",
            arguments: [p1]
        )
    }
    static var settingsImportModelTagPlaceholder: String {
        VyronResourceBundle.string("appSettingsImportModelTagPlaceholder", fallback: "my-model:latest")
    }
    static var settingsInstallOllama: String {
        VyronResourceBundle.string("appSettingsInstallOllama", fallback: "Install Ollama, then return here and refresh.")
    }
    static func settingsIntegerRequired(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsIntegerRequired",
            fallback: "%@ must be a whole number.",
            arguments: [p1]
        )
    }
    static var settingsInUse: String {
        VyronResourceBundle.string("appSettingsInUse", fallback: "In use")
    }
    static var settingsKeychainPlaceholder: String {
        VyronResourceBundle.string("appSettingsKeychainPlaceholder", fallback: "Saved in macOS Keychain")
    }
    static var settingsLocalInference: String {
        VyronResourceBundle.string("appSettingsLocalInference", fallback: "Local inference")
    }
    static var settingsLocalModelName: String {
        VyronResourceBundle.string("appSettingsLocalModelName", fallback: "Local model name")
    }
    static var settingsLocalModelSettings: String {
        VyronResourceBundle.string("appSettingsLocalModelSettings", fallback: "Local model settings")
    }
    static var settingsLocalServer: String {
        VyronResourceBundle.string("appSettingsLocalServer", fallback: "Local server")
    }
    static var settingsManualModelHint: String {
        VyronResourceBundle.string("appSettingsManualModelHint", fallback: "Enter the model ID manually if discovery is unavailable. Bit options appear when the server publishes distinct precision variants.")
    }
    static var settingsManualOnly: String {
        VyronResourceBundle.string("appSettingsManualOnly", fallback: "Manual only")
    }
    static var settingsMaxResponseTokens: String {
        VyronResourceBundle.string("appSettingsMaxResponseTokens", fallback: "Maximum response tokens")
    }
    static func settingsMemoryAmount(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsMemoryAmount",
            fallback: "%@ memory",
            arguments: [p1]
        )
    }
    static var settingsMemoryExplanation: String {
        VyronResourceBundle.string("appSettingsMemoryExplanation", fallback: "Download sizes describe model weights, not total running memory. Context, Xcode, Simulator, and other apps need additional memory. Agent tasks require working native tool calls; Chat can use models without tools.")
    }
    static var settingsMetaAPIKey: String {
        VyronResourceBundle.string("appSettingsMetaAPIKey", fallback: "Meta Model API key")
    }
    static var settingsMetaPrivacy: String {
        VyronResourceBundle.string("appSettingsMetaPrivacy", fallback: "Your prompts and selected project context are sent to Meta. Your API key is stored in macOS Keychain.")
    }
    static var settingsMissingFileDetails: String {
        VyronResourceBundle.string("appSettingsMissingFileDetails", fallback: "Size and precision are not published for this file.")
    }
    static var settingsMissingServerDetails: String {
        VyronResourceBundle.string("appSettingsMissingServerDetails", fallback: "Server does not publish model size or precision.")
    }
    static var settingsModelConnection: String {
        VyronResourceBundle.string("appSettingsModelConnection", fallback: "Model connection")
    }
    static var settingsModelDefault: String {
        VyronResourceBundle.string("appSettingsModelDefault", fallback: "Model default")
    }
    static var settingsModelDetails: String {
        VyronResourceBundle.string("appSettingsModelDetails", fallback: "Model details ↗")
    }
    static var settingsModelFilesReady: String {
        VyronResourceBundle.string("appSettingsModelFilesReady", fallback: "Model files are ready")
    }
    static var settingsModelID: String {
        VyronResourceBundle.string("appSettingsModelID", fallback: "Model ID")
    }
    static var settingsModelPrecision: String {
        VyronResourceBundle.string("appSettingsModelPrecision", fallback: "Model and precision")
    }
}
