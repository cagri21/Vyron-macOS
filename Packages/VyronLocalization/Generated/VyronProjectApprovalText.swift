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
}
