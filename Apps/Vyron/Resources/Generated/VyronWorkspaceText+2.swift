// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronWorkspaceText {
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
    static var inferenceSettings: String {
        VyronResourceBundle.string("workspaceInferenceSettings", fallback: "Model, effort, and speed")
    }
    static func localContextBudgetHint(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "workspaceLocalContextBudgetHint",
            fallback: "If your model supports a larger context, try increasing %@ in %@.",
            arguments: [p1, p2]
        )
    }
    static var lowEffort: String {
        VyronResourceBundle.string("workspaceLowEffort", fallback: "Low")
    }
    static var lowEffortDescription: String {
        VyronResourceBundle.string("workspaceLowEffortDescription", fallback: "Fast, contained edits and obvious tasks.")
    }
    static var manageModels: String {
        VyronResourceBundle.string("workspaceManageModels", fallback: "Manage Models…")
    }
    static var maxEffort: String {
        VyronResourceBundle.string("workspaceMaxEffort", fallback: "Max")
    }
    static var maxEffortDescription: String {
        VyronResourceBundle.string("workspaceMaxEffortDescription", fallback: "Hardest single, deeply complex problems.")
    }
    static var mediumEffort: String {
        VyronResourceBundle.string("workspaceMediumEffort", fallback: "Medium")
    }
    static var mediumEffortDescription: String {
        VyronResourceBundle.string("workspaceMediumEffortDescription", fallback: "Default setting for routine feature work and normal debugging.")
    }
    static var modelAndEffort: String {
        VyronResourceBundle.string("workspaceModelAndEffort", fallback: "Model and effort")
    }
    static var modeLocked: String {
        VyronResourceBundle.string("workspaceModeLocked", fallback: "Chat and Work stay fixed after the first message. Start a new chat to choose another mode.")
    }
    static var modelSelection: String {
        VyronResourceBundle.string("workspaceModelSelection", fallback: "Choose model")
    }
    static var newTask: String {
        VyronResourceBundle.string("workspaceNewTask", fallback: "New task")
    }
    static var openProject: String {
        VyronResourceBundle.string("workspaceOpenProject", fallback: "Open project")
    }
    static var placeholderChat: String {
        VyronResourceBundle.string("workspacePlaceholderChat", fallback: "Ask Vyron anything")
    }
    static var placeholderNoProject: String {
        VyronResourceBundle.string("workspacePlaceholderNoProject", fallback: "Open a project to start working…")
    }
    static var placeholderPlan: String {
        VyronResourceBundle.string("workspacePlaceholderPlan", fallback: "Plan with Vyron")
    }
    static var placeholderWork: String {
        VyronResourceBundle.string("workspacePlaceholderWork", fallback: "Work with Vyron")
    }
    static var plan: String {
        VyronResourceBundle.string("workspacePlan", fallback: "Plan")
    }
    static var planAccessDescription: String {
        VyronResourceBundle.string("workspacePlanAccessDescription", fallback: "Plan · Read-only reasoning · Switch to Agent to implement")
    }
    static var planning: String {
        VyronResourceBundle.string("workspacePlanning", fallback: "Planning")
    }
    static var planningApprovalScope: String {
        VyronResourceBundle.string("workspacePlanningApprovalScope", fallback: "Plan is read-only. Approval choices apply when planning is turned off.")
    }
    static var plugins: String {
        VyronResourceBundle.string("workspacePlugins", fallback: "Plugins")
    }
    static var projectAccess: String {
        VyronResourceBundle.string("workspaceProjectAccess", fallback: "Project access")
    }
    static var projectRequired: String {
        VyronResourceBundle.string("workspaceProjectRequired", fallback: "Choose a project to enable file edits and local commands.")
    }
    static func projectSetupFailure(_ p1: String) -> String {
        VyronResourceBundle.format(
            "workspaceProjectSetupFailure",
            fallback: "Project added, but some setup files could not be created: %@",
            arguments: [p1]
        )
    }
}
