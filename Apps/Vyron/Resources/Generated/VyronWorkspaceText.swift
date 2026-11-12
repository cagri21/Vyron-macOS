// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronWorkspaceText {
    static var addActions: String {
        VyronResourceBundle.string("workspaceAddActions", fallback: "Add actions")
    }
    static var advancedTools: String {
        VyronResourceBundle.string("workspaceAdvancedTools", fallback: "Mac & browser controls…")
    }
    static var agent: String {
        VyronResourceBundle.string("workspaceAgent", fallback: "Agent")
    }
    static var agentAccessDescription: String {
        VyronResourceBundle.string("workspaceAgentAccessDescription", fallback: "Agent · Reads and edits this project · Runs local checks")
    }
    static var approvalQuestion: String {
        VyronResourceBundle.string("workspaceApprovalQuestion", fallback: "How should Vyron actions be approved?")
    }
    static var approvalReviewReason: String {
        VyronResourceBundle.string("workspaceApprovalReviewReason", fallback: "Your approval setting requires a review before this project command runs.")
    }
    static var approvalScope: String {
        VyronResourceBundle.string("workspaceApprovalScope", fallback: "Edits stay inside the selected project. Blocked-command rules and separate plugin and Mac approvals still apply.")
    }
    static var approveForMe: String {
        VyronResourceBundle.string("workspaceApproveForMe", fallback: "Approve for me")
    }
    static var approveForMeDescription: String {
        VyronResourceBundle.string("workspaceApproveForMeDescription", fallback: "Run trusted commands automatically; ask for other allowed commands.")
    }
    static var askForApproval: String {
        VyronResourceBundle.string("workspaceAskForApproval", fallback: "Ask for approval")
    }
    static var askForApprovalDescription: String {
        VyronResourceBundle.string("workspaceAskForApprovalDescription", fallback: "Ask before running any project command.")
    }
    static var automaticEffort: String {
        VyronResourceBundle.string("workspaceAutomaticEffort", fallback: "Auto")
    }
    static var automaticEffortDescription: String {
        VyronResourceBundle.string("workspaceAutomaticEffortDescription", fallback: "Choose the effort for each task automatically.")
    }
    static var automaticModel: String {
        VyronResourceBundle.string("workspaceAutomaticModel", fallback: "Auto model")
    }
    static func automaticSelectedModel(_ p1: String) -> String {
        VyronResourceBundle.format(
            "workspaceAutomaticSelectedModel",
            fallback: "Auto · %@",
            arguments: [p1]
        )
    }
    static var balancedEffort: String {
        VyronResourceBundle.string("workspaceBalancedEffort", fallback: "Balanced")
    }
    static var chat: String {
        VyronResourceBundle.string("workspaceChat", fallback: "Chat")
    }
    static var chatAccessDescription: String {
        VyronResourceBundle.string("workspaceChatAccessDescription", fallback: "Chat · Read-only conversation")
    }
    static var chooseAutomaticModel: String {
        VyronResourceBundle.string("workspaceChooseAutomaticModel", fallback: "Auto — choose an installed model")
    }
    static var composerKeyboardHint: String {
        VyronResourceBundle.string("workspaceComposerKeyboardHint", fallback: "Return sends the message. Shift–Return adds a new line. Command–Return also sends.")
    }
    static var deepEffort: String {
        VyronResourceBundle.string("workspaceDeepEffort", fallback: "Deep")
    }
    static var dismissError: String {
        VyronResourceBundle.string("workspaceDismissError", fallback: "Dismiss error")
    }
    static var effort: String {
        VyronResourceBundle.string("workspaceEffort", fallback: "Effort")
    }
    static var extraHighEffort: String {
        VyronResourceBundle.string("workspaceExtraHighEffort", fallback: "Extra High")
    }
    static var extraHighEffortDescription: String {
        VyronResourceBundle.string("workspaceExtraHighEffortDescription", fallback: "Security audits, architecture updates, and migrations.")
    }
    static var fastSpeed: String {
        VyronResourceBundle.string("workspaceFastSpeed", fallback: "Fast")
    }
    static var fastSpeedDescription: String {
        VyronResourceBundle.string("workspaceFastSpeedDescription", fallback: "Faster OpenAI responses at higher API rates. Effort stays the same.")
    }
    static var fastSpeedUnavailable: String {
        VyronResourceBundle.string("workspaceFastSpeedUnavailable", fallback: "Fast is available with supported OpenAI models.")
    }
    static var files: String {
        VyronResourceBundle.string("workspaceFiles", fallback: "Files")
    }
    static var fullAccess: String {
        VyronResourceBundle.string("workspaceFullAccess", fallback: "Full access")
    }
    static var fullAccessDescription: String {
        VyronResourceBundle.string("workspaceFullAccessDescription", fallback: "Run all permitted project commands without asking.")
    }
    static var hideSidebar: String {
        VyronResourceBundle.string("workspaceHideSidebar", fallback: "Hide sidebar")
    }
    static var highEffort: String {
        VyronResourceBundle.string("workspaceHighEffort", fallback: "High")
    }
    static var highEffortDescription: String {
        VyronResourceBundle.string("workspaceHighEffortDescription", fallback: "Complex debugging, multi-file changes, and production risks.")
    }
    static func inferenceSelection(_ p1: String, _ p2: String, _ p3: String) -> String {
        VyronResourceBundle.format(
            "workspaceInferenceSelection",
            fallback: "Model: %@. Effort: %@. Speed: %@.",
            arguments: [p1, p2, p3]
        )
    }
}
