// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronControlText {
    static var penpotNotFound: String {
        VyronResourceBundle.string("controlPenpotNotFound", fallback: "No Penpot URL was found in your existing MCP configuration. Add it using the Penpot preset.")
    }
    static var planningFailed: String {
        VyronResourceBundle.string("controlPlanningFailed", fallback: "Task stopped because the next step could not be planned.")
    }
    static func planningStep(_ p1: String, _ p2: Int) -> String {
        VyronResourceBundle.format(
            "controlPlanningStep",
            fallback: "Reading %@ and planning step %d of 12…",
            arguments: [p1, p2]
        )
    }
    static var previewFailed: String {
        VyronResourceBundle.string("controlPreviewFailed", fallback: "Could not capture the app preview.")
    }
    static var previewLocal: String {
        VyronResourceBundle.string("controlPreviewLocal", fallback: "Preview stays on this Mac.")
    }
    static var previewPermission: String {
        VyronResourceBundle.string("controlPreviewPermission", fallback: "Allow screen recording to see the app while Vyron works.")
    }
    static var previewWaiting: String {
        VyronResourceBundle.string("controlPreviewWaiting", fallback: "Waiting for a visible app window")
    }
    static var proposalExpired: String {
        VyronResourceBundle.string("controlProposalExpired", fallback: "This proposal is out of date. Inspect the app and plan again.")
    }
    static var proposalOldSnapshot: String {
        VyronResourceBundle.string("controlProposalOldSnapshot", fallback: "Inspect the app and plan again. This proposal belongs to an older snapshot.")
    }
    static var proposalOnly: String {
        VyronResourceBundle.string("controlProposalOnly", fallback: "Proposal only. Review it below before choosing Execute.")
    }
    static func proposedAction(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlProposedAction",
            fallback: "Proposed %@. Waiting for your review; nothing has been executed.",
            arguments: [p1]
        )
    }
    static var readingNextState: String {
        VyronResourceBundle.string("controlReadingNextState", fallback: "Reading the next app state…")
    }
    static var readingSelectedApp: String {
        VyronResourceBundle.string("controlReadingSelectedApp", fallback: "Reading the selected app again…")
    }
    static var readingWebPage: String {
        VyronResourceBundle.string("controlReadingWebPage", fallback: "Reading a source")
    }
    static var readOnlyInspection: String {
        VyronResourceBundle.string("controlReadOnlyInspection", fallback: "Read-only app inspection.")
    }
    static func replaceElementReview(_ p1: Int, _ p2: String, _ p3: String) -> String {
        VyronResourceBundle.format(
            "controlReplaceElementReview",
            fallback: "Replace the value of element [%d].\n\n%@\n\nNew text:\n%@",
            arguments: [p1, p2, p3]
        )
    }
    static func replaceField(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlReplaceField",
            fallback: "\n\nReplace this field with:\n%@",
            arguments: [p1]
        )
    }
    static var replanning: String {
        VyronResourceBundle.string("controlReplanning", fallback: "Refreshing app state and replanning with greater effort.")
    }
    static var requestedInspection: String {
        VyronResourceBundle.string("controlRequestedInspection", fallback: "AI requested another read-only inspection: ")
    }
    static var resultInspectionFailed: String {
        VyronResourceBundle.string("controlResultInspectionFailed", fallback: "Task stopped because the action result could not be inspected. Verify the app before retrying.")
    }
    static var reviewBeforeContinue: String {
        VyronResourceBundle.string("controlReviewBeforeContinue", fallback: "Your review is needed before continuing.")
    }
    static func reviewNeeded(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlReviewNeeded",
            fallback: "Your review is needed: %@",
            arguments: [p1]
        )
    }
    static func reviewTarget(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "controlReviewTarget",
            fallback: "%@\n\nTarget: %@\n",
            arguments: [p1, p2]
        )
    }
    static func reviewTargetFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlReviewTargetFailed",
            fallback: "Action review could not verify its target: %@.",
            arguments: [p1]
        )
    }
    static func routineAllowed(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "controlRoutineAllowed",
            fallback: "Native checks allow a routine action in %@: %@",
            arguments: [p1, p2]
        )
    }
    static var safetyLimit: String {
        VyronResourceBundle.string("controlSafetyLimit", fallback: "Task paused at its safety limit: up to 12 planning passes and 8 approved actions. Review the latest snapshot.")
    }
    static var searchingWeb: String {
        VyronResourceBundle.string("controlSearchingWeb", fallback: "Searching the web")
    }
    static var selectedAppChanged: String {
        VyronResourceBundle.string("controlSelectedAppChanged", fallback: "Task stopped because the selected app changed.")
    }
    static func sendCommand(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlSendCommand",
            fallback: "Send the %@ key or browser command.",
            arguments: [p1]
        )
    }
    static func sendKeyReview(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlSendKeyReview",
            fallback: "Bring this app to the front and send %@.",
            arguments: [p1]
        )
    }
    static var settling: String {
        VyronResourceBundle.string("controlSettling", fallback: "Allowing the app to settle.")
    }
    static var snapshotExpiredPlanning: String {
        VyronResourceBundle.string("controlSnapshotExpiredPlanning", fallback: "Task stopped because the snapshot expired while planning. Start again to read the current app state.")
    }
    static var snapshotLocal: String {
        VyronResourceBundle.string("controlSnapshotLocal", fallback: "Snapshot captured locally. No AI request was made.")
    }
    static func snapshotPass(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "controlSnapshotPass",
            fallback: "Pass %d: fresh read-only snapshot captured.",
            arguments: [p1]
        )
    }
    static var snapshotTooOld: String {
        VyronResourceBundle.string("controlSnapshotTooOld", fallback: "This snapshot is older than 30 seconds. Inspect the app again, then review or plan the action again.")
    }
}
