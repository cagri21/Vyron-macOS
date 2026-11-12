// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronAppText {
    static func activityAccessibilityValue(_ p1: String, _ p2: String, _ p3: String) -> String {
        VyronResourceBundle.format(
            "appActivityAccessibilityValue",
            fallback: "%@, %@, %@",
            arguments: [p1, p2, p3]
        )
    }
    static func activityAfterStarting(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appActivityAfterStarting",
            fallback: "%@ after starting",
            arguments: [p1]
        )
    }
    static var activityCollapsed: String {
        VyronResourceBundle.string("appActivityCollapsed", fallback: "collapsed")
    }
    static var activityCompleted: String {
        VyronResourceBundle.string("appActivityCompleted", fallback: "Completed")
    }
    static var activityExpanded: String {
        VyronResourceBundle.string("appActivityExpanded", fallback: "expanded")
    }
    static var activityFailed: String {
        VyronResourceBundle.string("appActivityFailed", fallback: "Failed")
    }
    static var activityHide: String {
        VyronResourceBundle.string("appActivityHide", fallback: "Hide AI activity")
    }
    static var activityHideDetails: String {
        VyronResourceBundle.string("appActivityHideDetails", fallback: "Hide activity details")
    }
    static func activityMinutesSeconds(_ p1: Int, _ p2: Int) -> String {
        VyronResourceBundle.format(
            "appActivityMinutesSeconds",
            fallback: "%dm %ds",
            arguments: [p1, p2]
        )
    }
    static var activityPreparing: String {
        VyronResourceBundle.string("appActivityPreparing", fallback: "Preparing a response…")
    }
    static func activitySeconds(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "appActivitySeconds",
            fallback: "%ds",
            arguments: [p1]
        )
    }
    static var activitySharedProgress: String {
        VyronResourceBundle.string("appActivitySharedProgress", fallback: "Progress and explanations shared by the AI.")
    }
    static var activityShow: String {
        VyronResourceBundle.string("appActivityShow", fallback: "Show AI activity")
    }
    static var activityShowDetails: String {
        VyronResourceBundle.string("appActivityShowDetails", fallback: "Show activity details")
    }
    static var activityStopped: String {
        VyronResourceBundle.string("appActivityStopped", fallback: "Stopped")
    }
    static var activityTitle: String {
        VyronResourceBundle.string("appActivityTitle", fallback: "AI activity")
    }
    static var activityTools: String {
        VyronResourceBundle.string("appActivityTools", fallback: "Used tools")
    }
    static var activityWorking: String {
        VyronResourceBundle.string("appActivityWorking", fallback: "Working")
    }
    static var automationActionExample: String {
        VyronResourceBundle.string("appAutomationActionExample", fallback: "For example, focus the search field")
    }
    static var automationActivate: String {
        VyronResourceBundle.string("appAutomationActivate", fallback: "Activate")
    }
    static var automationActiveGoalHint: String {
        VyronResourceBundle.string("appAutomationActiveGoalHint", fallback: "Only works while this goal is active. Native app checks decide which actions can run. Stop cancels queued work.")
    }
    static var automationAdvanced: String {
        VyronResourceBundle.string("appAutomationAdvanced", fallback: "Advanced controls")
    }
    static var automationAgent: String {
        VyronResourceBundle.string("appAutomationAgent", fallback: "Agent")
    }
    static var automationAgentExample: String {
        VyronResourceBundle.string("appAutomationAgentExample", fallback: "For example, open Calculator and work out 18% of 2450")
    }
    static var automationAgentHint: String {
        VyronResourceBundle.string("appAutomationAgentHint", fallback: "Describe the outcome naturally. The agent chooses an app, adjusts its reasoning effort, performs routine actions, and decides when to check again. Sensitive or unfamiliar actions ask for your review.")
    }
    static var automationAIReport: String {
        VyronResourceBundle.string("appAutomationAIReport", fallback: "AI REPORT")
    }
    static var automationAllowControl: String {
        VyronResourceBundle.string("appAutomationAllowControl", fallback: "Allow Mac control…")
    }
    static var automationAuto: String {
        VyronResourceBundle.string("appAutomationAuto", fallback: "Auto")
    }
    static var automationAutoApps: String {
        VyronResourceBundle.string("appAutomationAutoApps", fallback: "Choose apps automatically")
    }
    static var automationAutoRoutine: String {
        VyronResourceBundle.string("appAutomationAutoRoutine", fallback: "Routine actions automatically")
    }
    static var automationAvailableApps: String {
        VyronResourceBundle.string("appAutomationAvailableApps", fallback: "Available apps")
    }
    static var automationBack: String {
        VyronResourceBundle.string("appAutomationBack", fallback: "Back")
    }
    static var automationBalanced: String {
        VyronResourceBundle.string("appAutomationBalanced", fallback: "Balanced")
    }
    static var automationBrowser: String {
        VyronResourceBundle.string("appAutomationBrowser", fallback: "04 / Browser")
    }
    static func automationBrowserCommandHint(_ p1: String) -> String {
        VyronResourceBundle.format(
            "appAutomationBrowserCommandHint",
            fallback: "%@ in the selected app",
            arguments: [p1]
        )
    }
}
