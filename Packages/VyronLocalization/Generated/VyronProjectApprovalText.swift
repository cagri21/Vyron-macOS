// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

package enum VyronProjectApprovalText {
    package static var commandMayChangeProjectFiles: String {
        VyronSharedResources.current.string("projectApprovalCommandMayChangeProjectFiles", fallback: "Review this local command before running it. Its project code may change files inside the selected project.")
    }

    package static func commandMayChangeProjectFiles(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalCommandMayChangeProjectFiles", fallback: "Review this local command before running it. Its project code may change files inside the selected project.", language: language)
    }
    package static var commandNeedsReview: String {
        VyronSharedResources.current.string("projectApprovalCommandNeedsReview", fallback: "Command needs your review")
    }

    package static func commandNeedsReview(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalCommandNeedsReview", fallback: "Command needs your review", language: language)
    }
    package static var commandNotPermitted: String {
        VyronSharedResources.current.string("projectApprovalCommandNotPermitted", fallback: "This command is not permitted in project mode.")
    }

    package static func commandNotPermitted(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalCommandNotPermitted", fallback: "This command is not permitted in project mode.", language: language)
    }
    package static var defaultReviewReason: String {
        VyronSharedResources.current.string("projectApprovalDefaultReviewReason", fallback: "Review this project command before it runs.")
    }

    package static func defaultReviewReason(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalDefaultReviewReason", fallback: "Review this project command before it runs.", language: language)
    }
    package static var gitCommandRequired: String {
        VyronSharedResources.current.string("projectApprovalGitCommandRequired", fallback: "Specify a local Git command in the selected project.")
    }

    package static func gitCommandRequired(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalGitCommandRequired", fallback: "Specify a local Git command in the selected project.", language: language)
    }
    package static var gitCommandUnavailable: String {
        VyronSharedResources.current.string("projectApprovalGitCommandUnavailable", fallback: "Use a supported local Git command. Git networking and changes to global Git settings are unavailable in Work.")
    }

    package static func gitCommandUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalGitCommandUnavailable", fallback: "Use a supported local Git command. Git networking and changes to global Git settings are unavailable in Work.", language: language)
    }
    package static var gitHardResetUnavailable: String {
        VyronSharedResources.current.string("projectApprovalGitHardResetUnavailable", fallback: "Git hard reset is unavailable in Work. Use a scoped reset or restore.")
    }

    package static func gitHardResetUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalGitHardResetUnavailable", fallback: "Git hard reset is unavailable in Work. Use a scoped reset or restore.", language: language)
    }
    package static var gitInspectionSideEffects: String {
        VyronSharedResources.current.string("projectApprovalGitInspectionSideEffects", fallback: "Remove Git inspection options that write files or run external helpers.")
    }

    package static func gitInspectionSideEffects(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalGitInspectionSideEffects", fallback: "Remove Git inspection options that write files or run external helpers.", language: language)
    }
    package static var gitInteractiveCommandUnavailable: String {
        VyronSharedResources.current.string("projectApprovalGitInteractiveCommandUnavailable", fallback: "Work supports noninteractive Git operations without scripts.")
    }

    package static func gitInteractiveCommandUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalGitInteractiveCommandUnavailable", fallback: "Work supports noninteractive Git operations without scripts.", language: language)
    }
    package static var responseUndoBusy: String {
        VyronSharedResources.current.string("projectApprovalResponseUndoBusy", fallback: "Wait for the project command to finish before undoing these edits.")
    }

    package static func responseUndoBusy(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("projectApprovalResponseUndoBusy", fallback: "Wait for the project command to finish before undoing these edits.", language: language)
    }
    package static func responseUndoConflict(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "projectApprovalResponseUndoConflict",
            fallback: "This response can’t be undone because a file changed. Your edits were preserved: %@",
            arguments: [p1],
            language: language
        )
    }
}
