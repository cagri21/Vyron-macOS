// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

package extension VyronModelDomainText {
    static func providerInvalidResponse(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainProviderInvalidResponse",
            fallback: "Could not read the model server response. %@",
            arguments: [p1],
            language: language
        )
    }
    static var providerModelListUnavailable: String {
        VyronSharedResources.current.string("modelDomainProviderModelListUnavailable", fallback: "This server does not provide model discovery. Enter its exact model ID manually.")
    }

    static func providerModelListUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainProviderModelListUnavailable", fallback: "This server does not provide model discovery. Enter its exact model ID manually.", language: language)
    }
    static var providerOutputLimitReached: String {
        VyronSharedResources.current.string("modelDomainProviderOutputLimitReached", fallback: "The model reached its output limit before completing the response. Try smaller file edits or increase the connection's output limit.")
    }

    static func providerOutputLimitReached(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainProviderOutputLimitReached", fallback: "The model reached its output limit before completing the response. Try smaller file edits or increase the connection's output limit.", language: language)
    }
    static var providerUnsupportedTools: String {
        VyronSharedResources.current.string("modelDomainProviderUnsupportedTools", fallback: "Native tool calling could not be verified for this model. Use Chat, or choose a model that supports tools.")
    }

    static func providerUnsupportedTools(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainProviderUnsupportedTools", fallback: "Native tool calling could not be verified for this model. Use Chat, or choose a model that supports tools.", language: language)
    }
    static var readingTask: String {
        VyronSharedResources.current.string("modelDomainReadingTask", fallback: "Reading the task")
    }

    static func readingTask(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainReadingTask", fallback: "Reading the task", language: language)
    }
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
    static func settingsOllamaDevelopmentTimeoutRange(_ p1: String, _ p2: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainSettingsOllamaDevelopmentTimeoutRange",
            fallback: "Enter a Work and Plan timeout between %1$@ and %2$@ seconds.",
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
    static var taskPagesUnread: String {
        VyronSharedResources.current.string("modelDomainTaskPagesUnread", fallback: "Work stopped because the original task text was not fully read. No project actions were permitted.")
    }

    static func taskPagesUnread(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainTaskPagesUnread", fallback: "Work stopped because the original task text was not fully read. No project actions were permitted.", language: language)
    }
    static var taskTextRead: String {
        VyronSharedResources.current.string("modelDomainTaskTextRead", fallback: "Task text read")
    }

    static func taskTextRead(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainTaskTextRead", fallback: "Task text read", language: language)
    }
}
