// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
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
            fallback: "%d-bit · %@",
            arguments: [p1, p2]
        )
    }
    static var settingsPrecisionHint: String {
        VyronResourceBundle.string("appSettingsPrecisionHint", fallback: "Precision selects the published weights. Running memory also includes context and other apps.")
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
    static var settingsQwen38Summary: String {
        VyronResourceBundle.string("appSettingsQwen38Summary", fallback: "Newer coding and reasoning model; recommended to try locally.")
    }
    static var settingsQwenCoderMemory: String {
        VyronResourceBundle.string("appSettingsQwenCoderMemory", fallback: "19 GB weights; start with a 32K context.")
    }
    static var settingsQwenCoderSummary: String {
        VyronResourceBundle.string("appSettingsQwenCoderSummary", fallback: "The coding baseline used for the app's initial build-and-repair proof.")
    }
    static var settingsQwenHelperMemory: String {
        VyronResourceBundle.string("appSettingsQwenHelperMemory", fallback: "2.5 GB download. Kept separate from coding-model selection.")
    }
    static var settingsQwenHelperSummary: String {
        VyronResourceBundle.string("appSettingsQwenHelperSummary", fallback: "Lightweight intent routing and chat helper; not a development model.")
    }
    static var settingsQwenNextMemory: String {
        VyronResourceBundle.string("appSettingsQwenNextMemory", fallback: "52 GB weights leave little headroom on a 64 GB Mac. Excluded from Auto.")
    }
    static var settingsQwenNextSummary: String {
        VyronResourceBundle.string("appSettingsQwenNextSummary", fallback: "Large agentic coding model. Optional, explicit selection only.")
    }
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
}
