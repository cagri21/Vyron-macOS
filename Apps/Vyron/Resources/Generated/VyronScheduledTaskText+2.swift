// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronScheduledTaskText {
    static var noTasksBody: String {
        VyronResourceBundle.string("noTasksBody", fallback: "Schedule a prompt once, daily, or weekly. Vyron keeps the results in your chats.")
    }
    static var noTasksTitle: String {
        VyronResourceBundle.string("noTasksTitle", fallback: "Make time for recurring work")
    }
    static var once: String {
        VyronResourceBundle.string("once", fallback: "Once")
    }
    static var openResult: String {
        VyronResourceBundle.string("openResult", fallback: "Open result")
    }
    static var pause: String {
        VyronResourceBundle.string("pause", fallback: "Pause")
    }
    static var paused: String {
        VyronResourceBundle.string("paused", fallback: "Paused")
    }
    static var plan: String {
        VyronResourceBundle.string("plan", fallback: "Plan")
    }
    static var preparingScheduled: String {
        VyronResourceBundle.string("preparingScheduled", fallback: "Preparing scheduled task")
    }
    static var project: String {
        VyronResourceBundle.string("project", fallback: "Project")
    }
    static var projectHint: String {
        VyronResourceBundle.string("projectHint", fallback: "The project and model are saved with this schedule.")
    }
    static var projectRequired: String {
        VyronResourceBundle.string("projectRequired", fallback: "Choose a project for Agent or Plan tasks.")
    }
    static var prompt: String {
        VyronResourceBundle.string("prompt", fallback: "Prompt")
    }
    static func promptTooLong(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "promptTooLong",
            fallback: "Keep the prompt under %@ KB. Agent and Plan prompts also need to stay within %@ characters.",
            arguments: [p1, p2]
        )
    }
    static var ready: String {
        VyronResourceBundle.string("ready", fallback: "Ready")
    }
    static var remove: String {
        VyronResourceBundle.string("remove", fallback: "Remove")
    }
    static var removeMessage: String {
        VyronResourceBundle.string("removeMessage", fallback: "The schedule will be removed. Its result chats will remain available.")
    }
    static var removeTitle: String {
        VyronResourceBundle.string("removeTitle", fallback: "Remove this schedule?")
    }
    static var repeatSchedule: String {
        VyronResourceBundle.string("repeatSchedule", fallback: "Repeat")
    }
    static var responseReady: String {
        VyronResourceBundle.string("responseReady", fallback: "Response ready")
    }
    static var resume: String {
        VyronResourceBundle.string("resume", fallback: "Resume")
    }
    static var retryStorage: String {
        VyronResourceBundle.string("retryStorage", fallback: "Retry loading")
    }
    static var reviewNote: String {
        VyronResourceBundle.string("reviewNote", fallback: "Scheduled tasks keep the same command review and connected-tool permissions as interactive tasks.")
    }
    static var running: String {
        VyronResourceBundle.string("running", fallback: "Running")
    }
    static var runningScheduledTask: String {
        VyronResourceBundle.string("runningScheduledTask", fallback: "Running scheduled task")
    }
    static var runNow: String {
        VyronResourceBundle.string("runNow", fallback: "Run now")
    }
    static var save: String {
        VyronResourceBundle.string("save", fallback: "Save schedule")
    }
    static var savedConnection: String {
        VyronResourceBundle.string("savedConnection", fallback: "Saved connection")
    }
    static var scheduledRun: String {
        VyronResourceBundle.string("scheduledRun", fallback: "Scheduled task")
    }
    static var scheduledTasks: String {
        VyronResourceBundle.string("scheduledTasks", fallback: "Scheduled tasks")
    }
    static var schedulerBusy: String {
        VyronResourceBundle.string("schedulerBusy", fallback: "A task is already running. Try again when it finishes.")
    }
    static var startsAt: String {
        VyronResourceBundle.string("startsAt", fallback: "First run")
    }
    static var stop: String {
        VyronResourceBundle.string("stop", fallback: "Stop")
    }
    static var stopped: String {
        VyronResourceBundle.string("stopped", fallback: "Stopped. Review any completed edits before running again.")
    }
    static var stoppedStatus: String {
        VyronResourceBundle.string("stoppedStatus", fallback: "Stopped")
    }
    static var storageRecovery: String {
        VyronResourceBundle.string("storageRecovery", fallback: "Scheduled tasks could not be loaded. The original file has been preserved.")
    }
}
