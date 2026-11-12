// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

package enum VyronModelDomainText {
    package static var agentApplicationAlreadyRunning: String {
        VyronSharedResources.current.string("modelDomainAgentApplicationAlreadyRunning", fallback: "Use activate or inspect for an application that is already running.")
    }

    package static func agentApplicationAlreadyRunning(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainAgentApplicationAlreadyRunning", fallback: "Use activate or inspect for an application that is already running.", language: language)
    }
    package static var agentApplicationUnavailable: String {
        VyronSharedResources.current.string("modelDomainAgentApplicationUnavailable", fallback: "The proposed application is outside the available application list.")
    }

    package static func agentApplicationUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainAgentApplicationUnavailable", fallback: "The proposed application is outside the available application list.", language: language)
    }
    package static var agentInputTooLarge: String {
        VyronSharedResources.current.string("modelDomainAgentInputTooLarge", fallback: "This task and application list exceed the local context budget. Use a shorter goal.")
    }

    package static func agentInputTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainAgentInputTooLarge", fallback: "This task and application list exceed the local context budget. Use a shorter goal.", language: language)
    }
    package static var agentInspectAgain: String {
        VyronSharedResources.current.string("modelDomainAgentInspectAgain", fallback: "Inspect this application again before acting on it or reporting completion.")
    }

    package static func agentInspectAgain(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainAgentInspectAgain", fallback: "Inspect this application again before acting on it or reporting completion.", language: language)
    }
    package static func agentInvalidDecision(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainAgentInvalidDecision",
            fallback: "The local agent step could not be used. %@",
            arguments: [p1],
            language: language
        )
    }
    package static func agentInvalidGoal(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainAgentInvalidGoal",
            fallback: "Describe a task using at most %@ characters.",
            arguments: [p1],
            language: language
        )
    }
    package static var agentLaunchBeforeInspecting: String {
        VyronSharedResources.current.string("modelDomainAgentLaunchBeforeInspecting", fallback: "Launch the selected application before inspecting or waiting for it.")
    }

    package static func agentLaunchBeforeInspecting(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainAgentLaunchBeforeInspecting", fallback: "Launch the selected application before inspecting or waiting for it.", language: language)
    }
    package static var agentLaunchBrowser: String {
        VyronSharedResources.current.string("modelDomainAgentLaunchBrowser", fallback: "Launch the browser before navigating.")
    }

    package static func agentLaunchBrowser(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainAgentLaunchBrowser", fallback: "Launch the browser before navigating.", language: language)
    }
    package static var agentNoApplications: String {
        VyronSharedResources.current.string("modelDomainAgentNoApplications", fallback: "No supported applications are available for this task.")
    }

    package static func agentNoApplications(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainAgentNoApplications", fallback: "No supported applications are available for this task.", language: language)
    }
    package static var agentNoEligibleModel: String {
        VyronSharedResources.current.string("modelDomainAgentNoEligibleModel", fallback: "Download a local chat model before starting an agent task.")
    }

    package static func agentNoEligibleModel(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainAgentNoEligibleModel", fallback: "Download a local chat model before starting an agent task.", language: language)
    }
    package static var balanceAuthenticationFailed: String {
        VyronSharedResources.current.string("modelDomainBalanceAuthenticationFailed", fallback: "The provider could not authorize the balance request.")
    }

    package static func balanceAuthenticationFailed(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainBalanceAuthenticationFailed", fallback: "The provider could not authorize the balance request.", language: language)
    }
    package static var balanceConnectionFailed: String {
        VyronSharedResources.current.string("modelDomainBalanceConnectionFailed", fallback: "Could not retrieve the provider's balance information.")
    }

    package static func balanceConnectionFailed(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainBalanceConnectionFailed", fallback: "Could not retrieve the provider's balance information.", language: language)
    }
    package static var balanceInvalidResponse: String {
        VyronSharedResources.current.string("modelDomainBalanceInvalidResponse", fallback: "The provider returned balance information that could not be read.")
    }

    package static func balanceInvalidResponse(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainBalanceInvalidResponse", fallback: "The provider returned balance information that could not be read.", language: language)
    }
    package static var balanceMissingKey: String {
        VyronSharedResources.current.string("modelDomainBalanceMissingKey", fallback: "Add a valid API key to check this connection's balance.")
    }

    package static func balanceMissingKey(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainBalanceMissingKey", fallback: "Add a valid API key to check this connection's balance.", language: language)
    }
    package static var balanceNoKeyLimit: String {
        VyronSharedResources.current.string("modelDomainBalanceNoKeyLimit", fallback: "This API key has no spending limit. This does not indicate an unlimited account balance.")
    }

    package static func balanceNoKeyLimit(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainBalanceNoKeyLimit", fallback: "This API key has no spending limit. This does not indicate an unlimited account balance.", language: language)
    }
    package static var balanceRateLimited: String {
        VyronSharedResources.current.string("modelDomainBalanceRateLimited", fallback: "The provider has limited balance requests. Try again later.")
    }

    package static func balanceRateLimited(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainBalanceRateLimited", fallback: "The provider has limited balance requests. Try again later.", language: language)
    }
    package static var balanceTemporarilyUnavailable: String {
        VyronSharedResources.current.string("modelDomainBalanceTemporarilyUnavailable", fallback: "The provider's balance information is temporarily unavailable.")
    }

    package static func balanceTemporarilyUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainBalanceTemporarilyUnavailable", fallback: "The provider's balance information is temporarily unavailable.", language: language)
    }
    package static var balanceUnsupported: String {
        VyronSharedResources.current.string("modelDomainBalanceUnsupported", fallback: "This connection does not provide a supported balance endpoint.")
    }

    package static func balanceUnsupported(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainBalanceUnsupported", fallback: "This connection does not provide a supported balance endpoint.", language: language)
    }
    package static var catalogLocalTagsOnly: String {
        VyronSharedResources.current.string("modelDomainCatalogLocalTagsOnly", fallback: "Only local model tags are supported.")
    }

    package static func catalogLocalTagsOnly(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainCatalogLocalTagsOnly", fallback: "Only local model tags are supported.", language: language)
    }
    package static var catalogModelReservedForChat: String {
        VyronSharedResources.current.string("modelDomainCatalogModelReservedForChat", fallback: "This lightweight model is reserved for routing and chat, not development.")
    }

    package static func catalogModelReservedForChat(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainCatalogModelReservedForChat", fallback: "This lightweight model is reserved for routing and chat, not development.", language: language)
    }
    package static var catalogNativeToolsUnavailable: String {
        VyronSharedResources.current.string("modelDomainCatalogNativeToolsUnavailable", fallback: "The installed model does not advertise native tool calling.")
    }

    package static func catalogNativeToolsUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainCatalogNativeToolsUnavailable", fallback: "The installed model does not advertise native tool calling.", language: language)
    }
    package static var catalogNativeToolsUnverified: String {
        VyronSharedResources.current.string("modelDomainCatalogNativeToolsUnverified", fallback: "Native tool support could not be verified for this installed model.")
    }

    package static func catalogNativeToolsUnverified(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainCatalogNativeToolsUnverified", fallback: "Native tool support could not be verified for this installed model.", language: language)
    }
    package static var contextBudget: String {
        VyronSharedResources.current.string("modelDomainContextBudget", fallback: "This tool exchange exceeds the local context budget. Narrow the requested change.")
    }

    package static func contextBudget(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainContextBudget", fallback: "This tool exchange exceeds the local context budget. Narrow the requested change.", language: language)
    }
    package static func controlInvalidInstruction(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainControlInvalidInstruction",
            fallback: "Describe one action using at most %@ characters.",
            arguments: [p1],
            language: language
        )
    }
    package static func controlInvalidProposal(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainControlInvalidProposal",
            fallback: "The local AI proposal could not be used. %@",
            arguments: [p1],
            language: language
        )
    }
    package static var controlRejectApplicationOnly: String {
        VyronSharedResources.current.string("modelDomainControlRejectApplicationOnly", fallback: "This action accepts only an application.")
    }

    package static func controlRejectApplicationOnly(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectApplicationOnly", fallback: "This action accepts only an application.", language: language)
    }
    package static var controlRejectApplicationRequired: String {
        VyronSharedResources.current.string("modelDomainControlRejectApplicationRequired", fallback: "Choose a running application first.")
    }

    package static func controlRejectApplicationRequired(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectApplicationRequired", fallback: "Choose a running application first.", language: language)
    }
    package static var controlRejectBrowserRequired: String {
        VyronSharedResources.current.string("modelDomainControlRejectBrowserRequired", fallback: "Browser navigation requires a supported browser.")
    }

    package static func controlRejectBrowserRequired(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectBrowserRequired", fallback: "Browser navigation requires a supported browser.", language: language)
    }
    package static var controlRejectElementMissingFromSnapshot: String {
        VyronSharedResources.current.string("modelDomainControlRejectElementMissingFromSnapshot", fallback: "The element is not present in the reviewed snapshot.")
    }

    package static func controlRejectElementMissingFromSnapshot(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectElementMissingFromSnapshot", fallback: "The element is not present in the reviewed snapshot.", language: language)
    }
    package static var controlRejectElementOutsideSnapshot: String {
        VyronSharedResources.current.string("modelDomainControlRejectElementOutsideSnapshot", fallback: "The element identifier is outside the snapshot.")
    }

    package static func controlRejectElementOutsideSnapshot(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectElementOutsideSnapshot", fallback: "The element identifier is outside the snapshot.", language: language)
    }
    package static var controlRejectElementRequired: String {
        VyronSharedResources.current.string("modelDomainControlRejectElementRequired", fallback: "Click requires one element from the snapshot.")
    }

    package static func controlRejectElementRequired(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectElementRequired", fallback: "Click requires one element from the snapshot.", language: language)
    }
    package static var controlRejectExplanationRequired: String {
        VyronSharedResources.current.string("modelDomainControlRejectExplanationRequired", fallback: "A short explanation is required.")
    }

    package static func controlRejectExplanationRequired(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectExplanationRequired", fallback: "A short explanation is required.", language: language)
    }
    package static var controlRejectInvalidTypedText: String {
        VyronSharedResources.current.string("modelDomainControlRejectInvalidTypedText", fallback: "Type requires bounded plain text in an application text field.")
    }

    package static func controlRejectInvalidTypedText(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectInvalidTypedText", fallback: "Type requires bounded plain text in an application text field.", language: language)
    }
    package static func controlRejectInvalidWait(_ p1: String, _ p2: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainControlRejectInvalidWait",
            fallback: "Wait requires %@ to %@ seconds and no other action payload.",
            arguments: [p1, p2],
            language: language
        )
    }
    package static var controlRejectInvalidWebURL: String {
        VyronSharedResources.current.string("modelDomainControlRejectInvalidWebURL", fallback: "Open a complete HTTP or HTTPS URL in the selected browser.")
    }

    package static func controlRejectInvalidWebURL(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectInvalidWebURL", fallback: "Open a complete HTTP or HTTPS URL in the selected browser.", language: language)
    }
}
