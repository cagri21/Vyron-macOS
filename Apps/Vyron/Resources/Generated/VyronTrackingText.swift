// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronTrackingText {
    static var agent: String {
        VyronResourceBundle.string("trackingAgent", fallback: "Vyron")
    }
    static var askedQuestions: String {
        VyronResourceBundle.string("trackingAskedQuestions", fallback: "asked questions")
    }
    static var back: String {
        VyronResourceBundle.string("trackingBack", fallback: "Back to activity")
    }
    static var close: String {
        VyronResourceBundle.string("trackingClose", fallback: "Close activity")
    }
    static var completed: String {
        VyronResourceBundle.string("trackingCompleted", fallback: "Completed")
    }
    static var details: String {
        VyronResourceBundle.string("trackingDetails", fallback: "Details")
    }
    static func durationMinutes(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "trackingDurationMinutes",
            fallback: "%dm",
            arguments: [p1]
        )
    }
    static var editedFiles: String {
        VyronResourceBundle.string("trackingEditedFiles", fallback: "edited files")
    }
    static var failed: String {
        VyronResourceBundle.string("trackingFailed", fallback: "Failed")
    }
    static func helpersStarted(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "trackingHelpersStarted",
            fallback: "%d helpers started working",
            arguments: [p1]
        )
    }
    static func helperStarted(_ p1: String) -> String {
        VyronResourceBundle.format(
            "trackingHelperStarted",
            fallback: "%@ started working",
            arguments: [p1]
        )
    }
    static var hideTimeline: String {
        VyronResourceBundle.string("trackingHideTimeline", fallback: "Hide task timeline")
    }
    static var model: String {
        VyronResourceBundle.string("trackingModel", fallback: "Model")
    }
    static var noActivity: String {
        VyronResourceBundle.string("trackingNoActivity", fallback: "Work activity appears here.")
    }
    static var noSubagents: String {
        VyronResourceBundle.string("trackingNoSubagents", fallback: "Parallel helpers appear here when started.")
    }
    static var parallelFinished: String {
        VyronResourceBundle.string("trackingParallelFinished", fallback: "Parallel helpers finished")
    }
    static var parallelStarted: String {
        VyronResourceBundle.string("trackingParallelStarted", fallback: "Running parallel helpers")
    }
    static var prompt: String {
        VyronResourceBundle.string("trackingPrompt", fallback: "Task")
    }
    static var ranCommands: String {
        VyronResourceBundle.string("trackingRanCommands", fallback: "ran commands")
    }
    static var readFiles: String {
        VyronResourceBundle.string("trackingReadFiles", fallback: "read files")
    }
    static var result: String {
        VyronResourceBundle.string("trackingResult", fallback: "Result")
    }
    static var running: String {
        VyronResourceBundle.string("trackingRunning", fallback: "Working")
    }
    static var searchedFiles: String {
        VyronResourceBundle.string("trackingSearchedFiles", fallback: "searched files")
    }
    static var showTimeline: String {
        VyronResourceBundle.string("trackingShowTimeline", fallback: "Show task timeline")
    }
    static var stopped: String {
        VyronResourceBundle.string("trackingStopped", fallback: "Stopped")
    }
    static var subagents: String {
        VyronResourceBundle.string("trackingSubagents", fallback: "Subagents")
    }
    static var task: String {
        VyronResourceBundle.string("trackingTask", fallback: "Task")
    }
    static var thinking: String {
        VyronResourceBundle.string("trackingThinking", fallback: "Thinking")
    }
    static var title: String {
        VyronResourceBundle.string("trackingTitle", fallback: "Activity")
    }
    static func todayAt(_ p1: String) -> String {
        VyronResourceBundle.format(
            "trackingTodayAt",
            fallback: "Today %@",
            arguments: [p1]
        )
    }
    static func toolsUsed(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "trackingToolsUsed",
            fallback: "%d tool steps",
            arguments: [p1]
        )
    }
    static var usedIntegrations: String {
        VyronResourceBundle.string("trackingUsedIntegrations", fallback: "used integrations")
    }
    static var viewActivity: String {
        VyronResourceBundle.string("trackingViewActivity", fallback: "View activity")
    }
    static func workedFor(_ p1: String) -> String {
        VyronResourceBundle.format(
            "trackingWorkedFor",
            fallback: "Worked for %@",
            arguments: [p1]
        )
    }
    static func workingFor(_ p1: String) -> String {
        VyronResourceBundle.format(
            "trackingWorkingFor",
            fallback: "Working for %@",
            arguments: [p1]
        )
    }
}
