// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

package extension VyronModelDomainText {
    static var routingClarification: String {
        VyronSharedResources.current.string("modelDomainRoutingClarification", fallback: "What would you like me to do on your Mac?")
    }

    static func routingClarification(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainRoutingClarification", fallback: "What would you like me to do on your Mac?", language: language)
    }
    static var routingInvalidRoute: String {
        VyronSharedResources.current.string("modelDomainRoutingInvalidRoute", fallback: "The local model could not clearly distinguish a conversation from a computer task. Please rephrase your request.")
    }

    static func routingInvalidRoute(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainRoutingInvalidRoute", fallback: "The local model could not clearly distinguish a conversation from a computer task. Please rephrase your request.", language: language)
    }
    static func routingInvalidText(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainRoutingInvalidText",
            fallback: "Enter a message under %@ KB.",
            arguments: [p1],
            language: language
        )
    }
    static func settingsContextRange(_ p1: String, _ p2: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainSettingsContextRange",
            fallback: "Context must be between %@ and %@ tokens.",
            arguments: [p1, p2],
            language: language
        )
    }
    static var settingsOutputExceedsContext: String {
        VyronSharedResources.current.string("modelDomainSettingsOutputExceedsContext", fallback: "Maximum output must be smaller than the context window.")
    }

    static func settingsOutputExceedsContext(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainSettingsOutputExceedsContext", fallback: "Maximum output must be smaller than the context window.", language: language)
    }
    static func settingsOutputRange(_ p1: String, _ p2: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainSettingsOutputRange",
            fallback: "Maximum output must be between %@ and %@ tokens.",
            arguments: [p1, p2],
            language: language
        )
    }
    static func settingsTemperatureRange(_ p1: String, _ p2: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainSettingsTemperatureRange",
            fallback: "Temperature must be between %@ and %@.",
            arguments: [p1, p2],
            language: language
        )
    }
    static var settingsThinkingConflict: String {
        VyronSharedResources.current.string("modelDomainSettingsThinkingConflict", fallback: "Choose either a thinking toggle or a thinking level.")
    }

    static func settingsThinkingConflict(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainSettingsThinkingConflict", fallback: "Choose either a thinking toggle or a thinking level.", language: language)
    }
    static func settingsTopPRange(_ p1: String, _ p2: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainSettingsTopPRange",
            fallback: "Top P must be between %@ and %@.",
            arguments: [p1, p2],
            language: language
        )
    }
}
