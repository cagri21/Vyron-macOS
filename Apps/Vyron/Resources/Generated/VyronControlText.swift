// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronControlText {
    static var accessibilityUnavailable: String {
        VyronResourceBundle.string("controlAccessibilityUnavailable", fallback: "Task stopped because Accessibility permission is unavailable.")
    }
    static var actionActivate: String {
        VyronResourceBundle.string("controlActionActivate", fallback: "Switched to the app")
    }
    static var actionClick: String {
        VyronResourceBundle.string("controlActionClick", fallback: "Clicked a control")
    }
    static func actionDescriptionLimit(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlActionDescriptionLimit",
            fallback: "Describe one action using %@ characters or fewer.",
            arguments: [p1]
        )
    }
    static var actionFailedStop: String {
        VyronResourceBundle.string("controlActionFailedStop", fallback: "Task stopped after an action failed. Inspect the app before retrying.")
    }
    static var actionInspect: String {
        VyronResourceBundle.string("controlActionInspect", fallback: "Read the app controls")
    }
    static var actionKey: String {
        VyronResourceBundle.string("controlActionKey", fallback: "Sent a keyboard command")
    }
    static var actionNavigate: String {
        VyronResourceBundle.string("controlActionNavigate", fallback: "Opened a web page")
    }
    static var actionNotPermitted: String {
        VyronResourceBundle.string("controlActionNotPermitted", fallback: "Agent stopped because the proposed action is not permitted.")
    }
    static var actionNotVerified: String {
        VyronResourceBundle.string("controlActionNotVerified", fallback: "Agent stopped because the action could not be verified. Restart to read the current app state.")
    }
    static var actionOpen: String {
        VyronResourceBundle.string("controlActionOpen", fallback: "Opened the app")
    }
    static var actionSent: String {
        VyronResourceBundle.string("controlActionSent", fallback: "Action sent. Inspect the app again to verify the result.")
    }
    static var actionType: String {
        VyronResourceBundle.string("controlActionType", fallback: "Entered text")
    }
    static var activateApp: String {
        VyronResourceBundle.string("controlActivateApp", fallback: "Bring this app to the front.")
    }
    static func activateReview(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlActivateReview",
            fallback: "Bring %@ to the front.",
            arguments: [p1]
        )
    }
    static func agentBudget(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "controlAgentBudget",
            fallback: "Agent stopped at its %d-step budget. Review its latest snapshot and progress before starting another goal.",
            arguments: [p1]
        )
    }
    static var agentStateUnreadable: String {
        VyronResourceBundle.string("controlAgentStateUnreadable", fallback: "Agent stopped because its current app state could not be read.")
    }
    static func agentTarget(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "controlAgentTarget",
            fallback: "%@\n\nTarget: %@\n",
            arguments: [p1, p2]
        )
    }
    static var agentVerificationFailed: String {
        VyronResourceBundle.string("controlAgentVerificationFailed", fallback: "Agent stopped because the next step or native app state could not be verified.")
    }
    static func allowAndRefresh(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlAllowAndRefresh",
            fallback: "Allow Vyron in %@, then refresh permissions.",
            arguments: [p1]
        )
    }
    static func allowAndStart(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlAllowAndStart",
            fallback: "Allow Vyron in %@, refresh permissions, then choose Start goal.",
            arguments: [p1]
        )
    }
    static func allowMacControl(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlAllowMacControl",
            fallback: "Allow Mac control in %@, then refresh permissions and choose Start goal.",
            arguments: [p1]
        )
    }
    static var allowPreview: String {
        VyronResourceBundle.string("controlAllowPreview", fallback: "Allow live preview")
    }
    static func appReadLocally(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlAppReadLocally",
            fallback: "Read %@ locally. No control action was needed.",
            arguments: [p1]
        )
    }
    static func appReviewNeeded(_ p1: String) -> String {
        VyronResourceBundle.format(
            "controlAppReviewNeeded",
            fallback: "Your review is needed in %@.",
            arguments: [p1]
        )
    }
    static var builtinRequired: String {
        VyronResourceBundle.string("controlBuiltinRequired", fallback: "Choose On this Mac in Manage Models to use Mac and browser controls. Custom model connections support Chat, Plan, and project Agent tasks.")
    }
    static func checkingAction(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "controlCheckingAction",
            fallback: "Checking the result of action %d…",
            arguments: [p1]
        )
    }
    static var chooseApp: String {
        VyronResourceBundle.string("controlChooseApp", fallback: "Choose an app, or turn on automatic app choice.")
    }
    static var choosingApp: String {
        VyronResourceBundle.string("controlChoosingApp", fallback: "Choosing where to work…")
    }
    static func clickElementReview(_ p1: Int, _ p2: String) -> String {
        VyronResourceBundle.format(
            "controlClickElementReview",
            fallback: "Bring this app to the front and click element [%d].\n\n%@",
            arguments: [p1, p2]
        )
    }
    static func clickReview(_ p1: String, _ p2: Int, _ p3: String) -> String {
        VyronResourceBundle.format(
            "controlClickReview",
            fallback: "Bring %@ to the front and click element [%d].\n\n%@",
            arguments: [p1, p2, p3]
        )
    }
    static var clickThisElement: String {
        VyronResourceBundle.string("controlClickThisElement", fallback: "\n\nClick this element.")
    }
    static var completeVerify: String {
        VyronResourceBundle.string("controlCompleteVerify", fallback: "AI reports completion. Verify the snapshot and its explanation.")
    }
    static var completeVerifyCurrent: String {
        VyronResourceBundle.string("controlCompleteVerifyCurrent", fallback: "AI reports completion. Verify the current snapshot and its explanation.")
    }
    static var completionOldSnapshot: String {
        VyronResourceBundle.string("controlCompletionOldSnapshot", fallback: "The completion report used an old snapshot. Inspect the app and plan again to verify the current state.")
    }
}
