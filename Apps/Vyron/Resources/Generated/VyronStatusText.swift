// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronStatusText {
    static func activeConnectionUnavailable(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusActiveConnectionUnavailable",
            fallback: "The active model connection could not be opened. Edit the connection to check its key. %@",
            arguments: [p1]
        )
    }
    static var agentConnectionVerified: String {
        VyronResourceBundle.string("statusAgentConnectionVerified", fallback: "Response received. Native Agent tools are supported.")
    }
    static var agentTraceHeading: String {
        VyronResourceBundle.string("statusAgentTraceHeading", fallback: "Agent trace")
    }
    static var aiExplanation: String {
        VyronResourceBundle.string("statusAiExplanation", fallback: "AI explanation")
    }
    static var automaticModelHint: String {
        VyronResourceBundle.string("statusAutomaticModelHint", fallback: "Auto can use compatible installed models.")
    }
    static var boundedContext: String {
        VyronResourceBundle.string("statusBoundedContext", fallback: "Using recent messages and bounded project excerpts. Your full conversation is saved.")
    }
    static func changedFiles(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "statusChangedFiles",
            fallback: "Changed files: %d",
            arguments: [p1]
        )
    }
    static var changedFilesHeading: String {
        VyronResourceBundle.string("statusChangedFilesHeading", fallback: "Changed files")
    }
    static func chatConnectionVerified(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusChatConnectionVerified",
            fallback: "Chat response received. Agent check: %@",
            arguments: [p1]
        )
    }
    static var checkingConnection: String {
        VyronResourceBundle.string("statusCheckingConnection", fallback: "Checking connection")
    }
    static var checksNotRun: String {
        VyronResourceBundle.string("statusChecksNotRun", fallback: "checks not run")
    }
    static var checksRunHeading: String {
        VyronResourceBundle.string("statusChecksRunHeading", fallback: "Checks run")
    }
    static var chooseWorkspace: String {
        VyronResourceBundle.string("statusChooseWorkspace", fallback: "Choose a workspace")
    }
    static var chooseWorkspaceHint: String {
        VyronResourceBundle.string("statusChooseWorkspaceHint", fallback: "Choose the project where the development agent can read files, make changes, and run local checks.")
    }
    static func commandExit(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "statusCommandExit",
            fallback: "exit %d",
            arguments: [p1]
        )
    }
    static var commandTimedOut: String {
        VyronResourceBundle.string("statusCommandTimedOut", fallback: "timed out")
    }
    static var computerWorkStopped: String {
        VyronResourceBundle.string("statusComputerWorkStopped", fallback: "Computer work stopped by you.")
    }
    static var computerWorkStoppedOnQuit: String {
        VyronResourceBundle.string("statusComputerWorkStoppedOnQuit", fallback: "Computer work stopped when Vyron quit.")
    }
    static var connectionChangeBusy: String {
        VyronResourceBundle.string("statusConnectionChangeBusy", fallback: "Finish or stop the current task or download before changing model connections.")
    }
    static func connectionConnected(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusConnectionConnected",
            fallback: "%@ connected",
            arguments: [p1]
        )
    }
    static func connectionNotResponding(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusConnectionNotResponding",
            fallback: "%@ is not responding.",
            arguments: [p1]
        )
    }
    static func connectionOffline(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusConnectionOffline",
            fallback: "%@ offline",
            arguments: [p1]
        )
    }
    static var connectionRemoved: String {
        VyronResourceBundle.string("statusConnectionRemoved", fallback: "Removed model connection.")
    }
    static func connectionSaved(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusConnectionSaved",
            fallback: "Saved %@.",
            arguments: [p1]
        )
    }
    static var connectionStorageRecovery: String {
        VyronResourceBundle.string("statusConnectionStorageRecovery", fallback: "The saved model connections need recovery before changes can be saved. The original file has been preserved.")
    }
    static var connectionUnavailable: String {
        VyronResourceBundle.string("statusConnectionUnavailable", fallback: "This model connection is no longer available.")
    }
    static func developmentFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusDevelopmentFailed",
            fallback: "Development stopped: %@\n\nReview completed edits in Changes and actual command output in Terminal.",
            arguments: [p1]
        )
    }
    static var developmentStopped: String {
        VyronResourceBundle.string("statusDevelopmentStopped", fallback: "Development task stopped.")
    }
    static var developmentStoppedOnQuit: String {
        VyronResourceBundle.string("statusDevelopmentStoppedOnQuit", fallback: "Development stopped when Vyron quit. Completed edits remain on disk; review them before continuing.")
    }
    static var developmentStoppedReview: String {
        VyronResourceBundle.string("statusDevelopmentStoppedReview", fallback: "Stopped. Completed project edits remain available in Changes. Review command output in Terminal before continuing.")
    }
    static func developmentSummary(_ p1: String, _ p2: String, _ p3: String) -> String {
        VyronResourceBundle.format(
            "statusDevelopmentSummary",
            fallback: "%@ · %@ · %@",
            arguments: [p1, p2, p3]
        )
    }
    static func developmentTaskTooLarge(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusDevelopmentTaskTooLarge",
            fallback: "The task description is too large. Use up to %@ KB of text.",
            arguments: [p1]
        )
    }
    static var downloadBeforeSelecting: String {
        VyronResourceBundle.string("statusDownloadBeforeSelecting", fallback: "Download this model before selecting it.")
    }
    static var downloadBusy: String {
        VyronResourceBundle.string("statusDownloadBusy", fallback: "Finish or stop the current task before downloading a model.")
    }
    static var downloadPaused: String {
        VyronResourceBundle.string("statusDownloadPaused", fallback: "Download paused. You can resume it at any time.")
    }
}
