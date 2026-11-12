// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronControlText {
    static var startingComputerTask: String {
        VyronResourceBundle.string("controlStartingComputerTask", fallback: "Starting Mac controls")
    }
    static func stepDetails(_ p1: Int, _ p2: String, _ p3: String, _ p4: String) -> String {
        VyronResourceBundle.format(
            "controlStepDetails",
            fallback: "Step %d · %@ · %@. %@",
            arguments: [p1, p2, p3, p4]
        )
    }
    static var stopBeforeManual: String {
        VyronResourceBundle.string("controlStopBeforeManual", fallback: "Stop the current task before using manual controls.")
    }
    static var stopBeforeMonitor: String {
        VyronResourceBundle.string("controlStopBeforeMonitor", fallback: "Stop the current task before starting a separate change monitor.")
    }
    static var stoppedByUser: String {
        VyronResourceBundle.string("controlStoppedByUser", fallback: "Task stopped by you.")
    }
    static var structureChanged: String {
        VyronResourceBundle.string("controlStructureChanged", fallback: "The visible app structure changed.")
    }
    static var suggestWait: String {
        VyronResourceBundle.string("controlSuggestWait", fallback: "The model suggests waiting. Use Agent mode for scheduled task steps.")
    }
    static var targetNotVerified: String {
        VyronResourceBundle.string("controlTargetNotVerified", fallback: "Agent stopped because the native target could not be verified.")
    }
    static var taskActionExpired: String {
        VyronResourceBundle.string("controlTaskActionExpired", fallback: "Task stopped because its proposed action expired. Start again to read the current app state.")
    }
    static var taskCompleteVerify: String {
        VyronResourceBundle.string("controlTaskCompleteVerify", fallback: "AI reports task complete — verify the snapshot.")
    }
    static func taskDescriptionLimit(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlTaskDescriptionLimit",
            fallback: "Describe the task using %@ characters or fewer.",
            arguments: [p1]
        )
    }
    static func taskStarted(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "controlTaskStarted",
            fallback: "Task started in %@. Goal: %@",
            arguments: [p1, p2]
        )
    }
    static var typeLimit: String {
        VyronResourceBundle.string("controlTypeLimit", fallback: "Enter text under 8 KB to place in the selected field.")
    }
    static func typeReview(_ p1: String, _ p2: Int, _ p3: String, _ p4: String) -> String {
        VyronResourceBundle.format(
            "controlTypeReview",
            fallback: "Bring %@ to the front and replace the value of element [%d].\n\n%@\n\nNew text:\n%@",
            arguments: [p1, p2, p3, p4]
        )
    }
    static var validElement: String {
        VyronResourceBundle.string("controlValidElement", fallback: "Enter an element number shown in the current snapshot, such as 1.")
    }
    static var validWebsite: String {
        VyronResourceBundle.string("controlValidWebsite", fallback: "Enter a valid website address beginning with https:// or http://.")
    }
    static func verificationFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlVerificationFailed",
            fallback: "Planning or native verification failed: %@.",
            arguments: [p1]
        )
    }
    static func waitingApproval(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "controlWaitingApproval",
            fallback: "Waiting for your approval · action %d of 8",
            arguments: [p1]
        )
    }
    static var waitingDownload: String {
        VyronResourceBundle.string("controlWaitingDownload", fallback: "Your goal is ready. Finish or pause the model download, then choose Start goal.")
    }
    static func waitingExplanation(_ p1: Int, _ p2: String) -> String {
        VyronResourceBundle.format(
            "controlWaitingExplanation",
            fallback: "Waiting %d seconds. %@",
            arguments: [p1, p2]
        )
    }
    static var waitingPermission: String {
        VyronResourceBundle.string("controlWaitingPermission", fallback: "Waiting for Mac control permission. Your goal is ready to start.")
    }
    static func waitingReason(_ p1: Int, _ p2: String) -> String {
        VyronResourceBundle.format(
            "controlWaitingReason",
            fallback: "Waiting %d seconds: %@",
            arguments: [p1, p2]
        )
    }
    static func waitingReview(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlWaitingReview",
            fallback: "Waiting for review: %@",
            arguments: [p1]
        )
    }
    static func waitingToRead(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "controlWaitingToRead",
            fallback: "Waiting %d seconds before reading the app again…",
            arguments: [p1]
        )
    }
    static func webLookupFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlWebLookupFailed",
            fallback: "The web lookup could not be completed. %@",
            arguments: [p1]
        )
    }
    static func workingInApp(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlWorkingInApp",
            fallback: "Working in %@…",
            arguments: [p1]
        )
    }
}
