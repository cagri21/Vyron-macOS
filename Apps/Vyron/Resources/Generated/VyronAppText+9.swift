// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
    static var settingsModelsDescription: String {
        VyronResourceBundle.string("appSettingsModelsDescription", fallback: "Use local models, connect a server by URL, or choose published model variants.")
    }
    static var settingsModelsHeading: String {
        VyronResourceBundle.string("appSettingsModelsHeading", fallback: "Your models, your settings")
    }
    static var settingsModelSourceURLPlaceholder: String {
        VyronResourceBundle.string("appSettingsModelSourceURLPlaceholder", fallback: "https://huggingface.co/owner/model-GGUF")
    }
    static var settingsMyModelServer: String {
        VyronResourceBundle.string("appSettingsMyModelServer", fallback: "My model server")
    }
    static var settingsNewConnection: String {
        VyronResourceBundle.string("appSettingsNewConnection", fallback: "New connection")
    }
    static var settingsNoModelsFromServer: String {
        VyronResourceBundle.string("appSettingsNoModelsFromServer", fallback: "The server did not list any models. Enter an exact model ID to test it.")
    }
    static var settingsNoReplacementVariants: String {
        VyronResourceBundle.string("appSettingsNoReplacementVariants", fallback: "No other precision variants are available for this model.")
    }
    static var settingsNoSupportedVariant: String {
        VyronResourceBundle.string("appSettingsNoSupportedVariant", fallback: "This source did not publish a supported model variant.")
    }
    static var settingsOllama: String {
        VyronResourceBundle.string("appSettingsOllama", fallback: "Ollama")
    }
    static var settingsOllamaDevelopmentTimeout: String {
        VyronResourceBundle.string("appSettingsOllamaDevelopmentTimeout", fallback: "Request timeout (seconds)")
    }
    static func settingsOllamaDevelopmentTimeoutHint(_ p1: String, _ p2: String, _ p3: String) -> String {
        VyronResourceBundle.format(
            "appSettingsOllamaDevelopmentTimeoutHint",
            fallback: "Enter %1$@–%2$@ seconds for each local Work or Plan request. Leave blank to use %3$@ seconds.",
            arguments: [p1, p2, p3]
        )
    }
    static var settingsOllamaTagHint: String {
        VyronResourceBundle.string("appSettingsOllamaTagHint", fallback: "Enter an Ollama tag. Downloads weights to this Mac; Agent compatibility is checked before a development task.")
    }
    static var settingsOllamaTagPlaceholder: String {
        VyronResourceBundle.string("appSettingsOllamaTagPlaceholder", fallback: "model-name:tag")
    }
    static func settingsOnDisk(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsOnDisk",
            fallback: "%@ on disk",
            arguments: [p1]
        )
    }
    static var settingsOneDownload: String {
        VyronResourceBundle.string("appSettingsOneDownload", fallback: "One download at a time")
    }
    static var settingsOptionalAPIKey: String {
        VyronResourceBundle.string("appSettingsOptionalAPIKey", fallback: "API key (optional)")
    }
    static var settingsOptionalHelper: String {
        VyronResourceBundle.string("appSettingsOptionalHelper", fallback: "Optional helper")
    }
    static var settingsOptionalSettings: String {
        VyronResourceBundle.string("appSettingsOptionalSettings", fallback: "Customized settings")
    }
    static var settingsOtherModels: String {
        VyronResourceBundle.string("appSettingsOtherModels", fallback: "Other models on this Mac")
    }
    static var settingsPause: String {
        VyronResourceBundle.string("appSettingsPause", fallback: "Pause")
    }
    static var settingsPaused: String {
        VyronResourceBundle.string("appSettingsPaused", fallback: "Paused")
    }
    static var settingsPrecision: String {
        VyronResourceBundle.string("appSettingsPrecision", fallback: "Bits / precision")
    }
    static func settingsPrecisionBits(_ p1: Int, _ p2: String) -> String {
        VyronResourceBundle.format(
            "appSettingsPrecisionBits",
            fallback: "%d-bit (%@)",
            arguments: [p1, p2]
        )
    }
    static var settingsPrecisionHint: String {
        VyronResourceBundle.string("appSettingsPrecisionHint", fallback: "Precision selects the published weights. Running memory also includes context and other apps.")
    }
    static func settingsPrecisionRemovalFailed(_ p1: String, _ p2: String, _ p3: String) -> String {
        VyronResourceBundle.format(
            "appSettingsPrecisionRemovalFailed",
            fallback: "Vyron selected %@. It couldn’t confirm removal of %@. %@",
            arguments: [p1, p2, p3]
        )
    }
    static func settingsPrecisionReplacementSucceeded(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "appSettingsPrecisionReplacementSucceeded",
            fallback: "Vyron selected %@ and removed %@ from this Mac.",
            arguments: [p1, p2]
        )
    }
    static var settingsPrecisionReplacementUnavailable: String {
        VyronResourceBundle.string("appSettingsPrecisionReplacementUnavailable", fallback: "This precision change is unavailable. Refresh the local model list and try again.")
    }
    static func settingsPrecisionReplacementWarning(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "appSettingsPrecisionReplacementWarning",
            fallback: "Vyron will remove %@ from this Mac after it verifies and selects %@. If the download or switch fails or is canceled, the current variant stays installed.",
            arguments: [p1, p2]
        )
    }
    static func settingsPrecisionSwitchCanceled(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appSettingsPrecisionSwitchCanceled",
            fallback: "Precision change canceled. Vyron kept %@ installed.",
            arguments: [p1]
        )
    }
    static func settingsPrecisionSwitchFailed(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "appSettingsPrecisionSwitchFailed",
            fallback: "Couldn’t switch precision. Vyron skipped removal of %@. %@",
            arguments: [p1, p2]
        )
    }
    static var settingsPrecisionVariantHint: String {
        VyronResourceBundle.string("appSettingsPrecisionVariantHint", fallback: "Each precision option selects an exact model variant on this server.")
    }
    static var settingsPreparingDownload: String {
        VyronResourceBundle.string("appSettingsPreparingDownload", fallback: "Preparing download…")
    }
    static var settingsQwen36Memory: String {
        VyronResourceBundle.string("appSettingsQwen36Memory", fallback: "23 GB weights; keep a 32K context and one model loaded.")
    }
    static var settingsQwen36Summary: String {
        VyronResourceBundle.string("appSettingsQwen36Summary", fallback: "Mixture-of-experts alternative for coding and reasoning.")
    }
    static var settingsQwen38Memory: String {
        VyronResourceBundle.string("appSettingsQwen38Memory", fallback: "Start with one loaded model and a 32K context.")
    }
}
