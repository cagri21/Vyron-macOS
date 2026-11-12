// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronControlText {
    static func connectedTools(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "controlConnectedTools",
            fallback: "Connected · %d tools",
            arguments: [p1]
        )
    }
    static var connecting: String {
        VyronResourceBundle.string("controlConnecting", fallback: "Connecting…")
    }
    static var connectionFailed: String {
        VyronResourceBundle.string("controlConnectionFailed", fallback: "Connection failed")
    }
    static var decidingNextStep: String {
        VyronResourceBundle.string("controlDecidingNextStep", fallback: "Deciding the next step for your goal…")
    }
    static var defaultBrowser: String {
        VyronResourceBundle.string("controlDefaultBrowser", fallback: "your default browser")
    }
    static var defaultBrowserReview: String {
        VyronResourceBundle.string("controlDefaultBrowserReview", fallback: "Opening the default browser requires your review.")
    }
    static var disconnected: String {
        VyronResourceBundle.string("controlDisconnected", fallback: "Disconnected")
    }
    static func elementFromSnapshot(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "controlElementFromSnapshot",
            fallback: "Element [%d] from the current inspection.",
            arguments: [p1]
        )
    }
    static var evidence: String {
        VyronResourceBundle.string("controlEvidence", fallback: " Evidence: ")
    }
    static var freshSnapshot: String {
        VyronResourceBundle.string("controlFreshSnapshot", fallback: "Fresh snapshot captured locally.")
    }
    static func goalDescriptionLimit(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlGoalDescriptionLimit",
            fallback: "Describe your goal using %@ characters or fewer.",
            arguments: [p1]
        )
    }
    static var goalNotStarted: String {
        VyronResourceBundle.string("controlGoalNotStarted", fallback: "Computer work was not started. The control panel closed before the goal began.")
    }
    static var inspectionFailed: String {
        VyronResourceBundle.string("controlInspectionFailed", fallback: "Task stopped because the app could not be inspected.")
    }
    static var inspectOnlyReview: String {
        VyronResourceBundle.string("controlInspectOnlyReview", fallback: "Read a new Accessibility snapshot. No control action.")
    }
    static func keyReview(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "controlKeyReview",
            fallback: "Bring %@ to the front and send the %@ key or browser command.",
            arguments: [p1, p2]
        )
    }
    static var livePreview: String {
        VyronResourceBundle.string("controlLivePreview", fallback: "Live Mac preview")
    }
    static var mcpChanged: String {
        VyronResourceBundle.string("controlMcpChanged", fallback: "The MCP connection changed. Reconnect it and start a new task.")
    }
    static var mcpDisconnected: String {
        VyronResourceBundle.string("controlMcpDisconnected", fallback: "This MCP connection was disconnected.")
    }
    static var mcpReadOnly: String {
        VyronResourceBundle.string("controlMcpReadOnly", fallback: "This connection permits read-only tools.")
    }
    static var mcpResolveFile: String {
        VyronResourceBundle.string("controlMcpResolveFile", fallback: "Resolve the unreadable MCP connections file before saving changes.")
    }
    static var mcpToolLimit: String {
        VyronResourceBundle.string("controlMcpToolLimit", fallback: "More than 64 MCP tools are connected. Disconnect unused servers before starting a task.")
    }
    static var mcpUnreadable: String {
        VyronResourceBundle.string("controlMcpUnreadable", fallback: "Saved MCP connections could not be read. The original file has been preserved.")
    }
    static var monitorPermission: String {
        VyronResourceBundle.string("controlMonitorPermission", fallback: "Choose an app and allow Accessibility before starting the monitor.")
    }
    static func monitorStarted(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlMonitorStarted",
            fallback: "Monitoring started for %@. Initial snapshot captured.",
            arguments: [p1]
        )
    }
    static func monitorStopped(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlMonitorStopped",
            fallback: "Monitoring stopped. %@",
            arguments: [p1]
        )
    }
    static var nextActionNotPermitted: String {
        VyronResourceBundle.string("controlNextActionNotPermitted", fallback: "Agent stopped because its next action is not permitted.")
    }
    static var noPermittedApp: String {
        VyronResourceBundle.string("controlNoPermittedApp", fallback: "No permitted app is available for this goal.")
    }
    static var noVisibleChange: String {
        VyronResourceBundle.string("controlNoVisibleChange", fallback: "No visible text change was observed.")
    }
    static func observedAction(_ p1: Int, _ p2: String, _ p3: String) -> String {
        VyronResourceBundle.format(
            "controlObservedAction",
            fallback: "Approved action %d: %@\nObserved: %@",
            arguments: [p1, p2, p3]
        )
    }
    static var openInstalledApp: String {
        VyronResourceBundle.string("controlOpenInstalledApp", fallback: "Open this installed app.")
    }
    static func openSelectedURL(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlOpenSelectedURL",
            fallback: "Open this URL in the selected browser:\n%@",
            arguments: [p1]
        )
    }
    static func openURLReview(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "controlOpenURLReview",
            fallback: "Open %@ in %@.",
            arguments: [p1, p2]
        )
    }
    static func openWebsite(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlOpenWebsite",
            fallback: "Open this website:\n%@",
            arguments: [p1]
        )
    }
    static var panelClosed: String {
        VyronResourceBundle.string("controlPanelClosed", fallback: "Task stopped when the panel closed.")
    }
    static var penpotImportFailed: String {
        VyronResourceBundle.string("controlPenpotImportFailed", fallback: "The existing Penpot connection could not be imported. Add its URL using the Penpot preset.")
    }
}
