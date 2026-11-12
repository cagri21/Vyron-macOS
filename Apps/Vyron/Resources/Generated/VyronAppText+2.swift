// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
    static var automationBrowserHint: String {
        VyronResourceBundle.string("appAutomationBrowserHint", fallback: "Back, Forward, and Reload act on the selected running app. Website access uses your browser’s normal connection.")
    }
    static func automationCapturedAge(_ p1: Int, _ p2: String) -> String {
        VyronResourceBundle.format(
            "appAutomationCapturedAge",
            fallback: "Captured %ds ago · %@",
            arguments: [p1, p2]
        )
    }
    static var automationChangesHint: String {
        VyronResourceBundle.string("appAutomationChangesHint", fallback: "Changes will appear here. The latest 30 events stay in this panel only.")
    }
    static var automationClearEvents: String {
        VyronResourceBundle.string("appAutomationClearEvents", fallback: "Clear events")
    }
    static var automationClick: String {
        VyronResourceBundle.string("appAutomationClick", fallback: "Click…")
    }
    static var automationClose: String {
        VyronResourceBundle.string("appAutomationClose", fallback: "Close and stop monitoring")
    }
    static var automationControlRequired: String {
        VyronResourceBundle.string("appAutomationControlRequired", fallback: "Required to inspect and operate the app you select.")
    }
    static var automationCPU: String {
        VyronResourceBundle.string("appAutomationCPU", fallback: "CPU")
    }
    static var automationCurrentAppState: String {
        VyronResourceBundle.string("appAutomationCurrentAppState", fallback: "Current app state")
    }
    static func automationDecisionBudget(_ p1: String, _ p2: String, _ p3: String, _ p4: String) -> String {
        VyronResourceBundle.format(
            "appAutomationDecisionBudget",
            fallback: "%@ effort · %@ context tokens · %@ reply tokens · %@",
            arguments: [p1, p2, p3, p4]
        )
    }
    static func automationDecisionCounts(_ p1: Int, _ p2: Int, _ p3: Int) -> String {
        VyronResourceBundle.format(
            "appAutomationDecisionCounts",
            fallback: "%d/%d decisions · %d actions performed",
            arguments: [p1, p2, p3]
        )
    }
    static var automationDeep: String {
        VyronResourceBundle.string("appAutomationDeep", fallback: "Deep")
    }
    static var automationDefaultBrowser: String {
        VyronResourceBundle.string("appAutomationDefaultBrowser", fallback: "Default browser")
    }
    static var automationDescription: String {
        VyronResourceBundle.string("appAutomationDescription", fallback: "Say what you want done. Your local agent chooses where to work and follows the result.")
    }
    static var automationDiscussSnapshot: String {
        VyronResourceBundle.string("appAutomationDiscussSnapshot", fallback: "Ask AI about snapshot →")
    }
    static var automationDiskFree: String {
        VyronResourceBundle.string("appAutomationDiskFree", fallback: "Disk free")
    }
    static var automationDownKey: String {
        VyronResourceBundle.string("appAutomationDownKey", fallback: "Down")
    }
    static var automationEffort: String {
        VyronResourceBundle.string("appAutomationEffort", fallback: "Effort")
    }
    static var automationElement: String {
        VyronResourceBundle.string("appAutomationElement", fallback: "Element")
    }
    static var automationElementHint: String {
        VyronResourceBundle.string("appAutomationElementHint", fallback: "Use an element number from the snapshot. Every action shows its target and text before you approve it.")
    }
    static var automationElementID: String {
        VyronResourceBundle.string("appAutomationElementID", fallback: "Element ID")
    }
    static var automationEscapeKey: String {
        VyronResourceBundle.string("appAutomationEscapeKey", fallback: "Escape")
    }
    static var automationEvery: String {
        VyronResourceBundle.string("appAutomationEvery", fallback: "Every")
    }
    static var automationExecute: String {
        VyronResourceBundle.string("appAutomationExecute", fallback: "Execute action")
    }
    static var automationForward: String {
        VyronResourceBundle.string("appAutomationForward", fallback: "Forward")
    }
    static var automationFreshReadsHint: String {
        VyronResourceBundle.string("appAutomationFreshReadsHint", fallback: "Fresh reads happen automatically. Each control action waits for your review. Stop cancels all queued work.")
    }
    static var automationHeading: String {
        VyronResourceBundle.string("appAutomationHeading", fallback: "Your Mac, with your permission")
    }
    static var automationInspect: String {
        VyronResourceBundle.string("appAutomationInspect", fallback: "Inspect app")
    }
    static var automationInspectAgain: String {
        VyronResourceBundle.string("appAutomationInspectAgain", fallback: "inspect again before acting")
    }
    static var automationInstalledNotOpen: String {
        VyronResourceBundle.string("appAutomationInstalledNotOpen", fallback: "Installed · not open")
    }
    static var automationKey: String {
        VyronResourceBundle.string("appAutomationKey", fallback: "Key")
    }
    static var automationLeftKey: String {
        VyronResourceBundle.string("appAutomationLeftKey", fallback: "Left")
    }
    static var automationLocalRequired: String {
        VyronResourceBundle.string("appAutomationLocalRequired", fallback: "Choose On this Mac in Manage Models to use computer controls. Custom connections are available for Chat, Plan, and project Agent tasks.")
    }
    static var automationMacControl: String {
        VyronResourceBundle.string("appAutomationMacControl", fallback: "Mac control")
    }
    static var automationManualControls: String {
        VyronResourceBundle.string("appAutomationManualControls", fallback: "03 / Manual controls")
    }
}
