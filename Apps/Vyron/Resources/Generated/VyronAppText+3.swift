// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronAppText {
    static var automationMeasuring: String {
        VyronResourceBundle.string("appAutomationMeasuring", fallback: "Measuring")
    }
    static var automationMemoryFree: String {
        VyronResourceBundle.string("appAutomationMemoryFree", fallback: "Memory currently free")
    }
    static var automationMode: String {
        VyronResourceBundle.string("appAutomationMode", fallback: "Mode")
    }
    static var automationMonitor: String {
        VyronResourceBundle.string("appAutomationMonitor", fallback: "Monitor")
    }
    static var automationMonitorHint: String {
        VyronResourceBundle.string("appAutomationMonitorHint", fallback: "Reads only the app you select. No automatic AI requests or control actions. Monitoring stops when you close this panel or select another app.")
    }
    static func automationNextCheck(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "appAutomationNextCheck",
            fallback: "Next check in %ds",
            arguments: [p1]
        )
    }
    static var automationOneAction: String {
        VyronResourceBundle.string("appAutomationOneAction", fallback: "One action")
    }
    static var automationOneActionHint: String {
        VyronResourceBundle.string("appAutomationOneActionHint", fallback: "Describe one action. The model proposes a step for you to review; it never executes the proposal itself.")
    }
    static var automationOpenIn: String {
        VyronResourceBundle.string("appAutomationOpenIn", fallback: "Open in")
    }
    static var automationOpenURL: String {
        VyronResourceBundle.string("appAutomationOpenURL", fallback: "Open URL…")
    }
    static var automationPlanAction: String {
        VyronResourceBundle.string("appAutomationPlanAction", fallback: "Plan action")
    }
    static func automationPlanningCounts(_ p1: Int, _ p2: Int) -> String {
        VyronResourceBundle.format(
            "appAutomationPlanningCounts",
            fallback: "%d/12 planning passes · %d/8 approved actions",
            arguments: [p1, p2]
        )
    }
    static var automationPrivacySettings: String {
        VyronResourceBundle.string("appAutomationPrivacySettings", fallback: "Open Privacy Settings…")
    }
    static var automationProposal: String {
        VyronResourceBundle.string("appAutomationProposal", fallback: "PROPOSAL")
    }
    static var automationQuick: String {
        VyronResourceBundle.string("appAutomationQuick", fallback: "Quick")
    }
    static var automationReadyForReview: String {
        VyronResourceBundle.string("appAutomationReadyForReview", fallback: "ready for review")
    }
    static var automationRefreshApps: String {
        VyronResourceBundle.string("appAutomationRefreshApps", fallback: "Refresh apps and permissions")
    }
    static var automationReload: String {
        VyronResourceBundle.string("appAutomationReload", fallback: "Reload")
    }
    static var automationReturnKey: String {
        VyronResourceBundle.string("appAutomationReturnKey", fallback: "Return")
    }
    static var automationReviewAction: String {
        VyronResourceBundle.string("appAutomationReviewAction", fallback: "Review this action")
    }
    static var automationReviewExecute: String {
        VyronResourceBundle.string("appAutomationReviewExecute", fallback: "Review & execute…")
    }
    static var automationReviewHint: String {
        VyronResourceBundle.string("appAutomationReviewHint", fallback: "Works locally while your goal is active. Sensitive or unfamiliar actions wait for your review.")
    }
    static var automationReviewSteps: String {
        VyronResourceBundle.string("appAutomationReviewSteps", fallback: "Review each step")
    }
    static var automationRightKey: String {
        VyronResourceBundle.string("appAutomationRightKey", fallback: "Right")
    }
    static var automationRunningApps: String {
        VyronResourceBundle.string("appAutomationRunningApps", fallback: "Running apps")
    }
    static func automationSeconds(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "appAutomationSeconds",
            fallback: "%ds",
            arguments: [p1]
        )
    }
    static var automationSeeExposed: String {
        VyronResourceBundle.string("appAutomationSeeExposed", fallback: "See what the selected app exposes.")
    }
    static var automationSelectedApp: String {
        VyronResourceBundle.string("appAutomationSelectedApp", fallback: "Selected app")
    }
    static var automationSendKey: String {
        VyronResourceBundle.string("appAutomationSendKey", fallback: "Send key…")
    }
    static var automationSnapshotDescription: String {
        VyronResourceBundle.string("appAutomationSnapshotDescription", fallback: "A local text snapshot of windows, controls, and visible labels.")
    }
    static var automationSpaceKey: String {
        VyronResourceBundle.string("appAutomationSpaceKey", fallback: "Space")
    }
    static var automationStartGoal: String {
        VyronResourceBundle.string("appAutomationStartGoal", fallback: "Start goal")
    }
    static var automationStop: String {
        VyronResourceBundle.string("appAutomationStop", fallback: "Stop")
    }
    static var automationStopTask: String {
        VyronResourceBundle.string("appAutomationStopTask", fallback: "Stop task")
    }
    static var automationTabKey: String {
        VyronResourceBundle.string("appAutomationTabKey", fallback: "Tab")
    }
}
