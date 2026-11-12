// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronScheduledTaskText {
    static var activeTaskLocked: String {
        VyronResourceBundle.string("activeTaskLocked", fallback: "Stop the running task before editing or removing it.")
    }
    static var addTask: String {
        VyronResourceBundle.string("addTask", fallback: "Add scheduled task")
    }
    static var agent: String {
        VyronResourceBundle.string("agent", fallback: "Agent")
    }
    static var automaticModel: String {
        VyronResourceBundle.string("automaticModel", fallback: "Auto model")
    }
    static var cancel: String {
        VyronResourceBundle.string("cancel", fallback: "Cancel")
    }
    static var chat: String {
        VyronResourceBundle.string("chat", fallback: "Chat")
    }
    static var close: String {
        VyronResourceBundle.string("close", fallback: "Close")
    }
    static var completed: String {
        VyronResourceBundle.string("completed", fallback: "Scheduled task completed.")
    }
    static var completedStatus: String {
        VyronResourceBundle.string("completedStatus", fallback: "Completed")
    }
    static var connection: String {
        VyronResourceBundle.string("connection", fallback: "Connection")
    }
    static var connectionMissing: String {
        VyronResourceBundle.string("connectionMissing", fallback: "The saved model connection is no longer available. Edit this schedule to choose a connection.")
    }
    static var daily: String {
        VyronResourceBundle.string("daily", fallback: "Daily")
    }
    static var edit: String {
        VyronResourceBundle.string("edit", fallback: "Edit")
    }
    static var editorHint: String {
        VyronResourceBundle.string("editorHint", fallback: "Choose Chat for a prompt without a project.")
    }
    static var editTask: String {
        VyronResourceBundle.string("editTask", fallback: "Edit scheduled task")
    }
    static var enabled: String {
        VyronResourceBundle.string("enabled", fallback: "Enabled")
    }
    static var executionNote: String {
        VyronResourceBundle.string("executionNote", fallback: "Runs while Vyron is open and your Mac is awake. After sleep or reopening, an overdue schedule runs once. Vyron does not wake your Mac.")
    }
    static var failed: String {
        VyronResourceBundle.string("failed", fallback: "Scheduled task failed.")
    }
    static var failedStatus: String {
        VyronResourceBundle.string("failedStatus", fallback: "Failed")
    }
    static var historyUnavailable: String {
        VyronResourceBundle.string("historyUnavailable", fallback: "Conversation history could not be saved. This task was not started.")
    }
    static var interrupted: String {
        VyronResourceBundle.string("interrupted", fallback: "Interrupted when Vyron closed. Review the result before running it again.")
    }
    static var interruptedStatus: String {
        VyronResourceBundle.string("interruptedStatus", fallback: "Interrupted")
    }
    static var invalidDate: String {
        VyronResourceBundle.string("invalidDate", fallback: "Choose a future time for a one-time task.")
    }
    static var invalidPrompt: String {
        VyronResourceBundle.string("invalidPrompt", fallback: "Enter the prompt Vyron should run.")
    }
    static var invalidSchedule: String {
        VyronResourceBundle.string("invalidSchedule", fallback: "Choose a valid future date and time zone for this schedule.")
    }
    static var invalidStore: String {
        VyronResourceBundle.string("invalidStore", fallback: "The saved scheduled tasks could not be read. The original file has been preserved.")
    }
    static func invalidTask(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "invalidTask",
            fallback: "Enter a title, prompt, and model. Agent and Plan prompts support up to %@ characters; all prompts support up to %@ KB.",
            arguments: [p1, p2]
        )
    }
    static var invalidTitle: String {
        VyronResourceBundle.string("invalidTitle", fallback: "Enter a title of up to 160 characters for this schedule.")
    }
    static var lastRun: String {
        VyronResourceBundle.string("lastRun", fallback: "Last run")
    }
    static var mode: String {
        VyronResourceBundle.string("mode", fallback: "Mode")
    }
    static var model: String {
        VyronResourceBundle.string("model", fallback: "Model")
    }
    static var nextRun: String {
        VyronResourceBundle.string("nextRun", fallback: "Next run")
    }
    static var noAutomaticModel: String {
        VyronResourceBundle.string("noAutomaticModel", fallback: "No installed model is eligible for Auto.")
    }
    static var noNextRun: String {
        VyronResourceBundle.string("noNextRun", fallback: "No upcoming run")
    }
    static var noProject: String {
        VyronResourceBundle.string("noProject", fallback: "No project selected")
    }
}
