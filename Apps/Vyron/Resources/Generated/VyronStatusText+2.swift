// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronStatusText {
    static func downloadingModel(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusDownloadingModel",
            fallback: "Downloading %@ · Pause in Manage Models to run a task.",
            arguments: [p1]
        )
    }
    static func downloadingVariant(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusDownloadingVariant",
            fallback: "Downloading %@…",
            arguments: [p1]
        )
    }
    static var downloadToBegin: String {
        VyronResourceBundle.string("statusDownloadToBegin", fallback: "Download a model to begin.")
    }
    static var finished: String {
        VyronResourceBundle.string("statusFinished", fallback: "Finished")
    }
    static var historyDeleteUnavailable: String {
        VyronResourceBundle.string("statusHistoryDeleteUnavailable", fallback: "The chat could not be deleted while conversation history needs recovery.")
    }
    static func historyOpenFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusHistoryOpenFailed",
            fallback: "Your conversation history could not be opened. %@",
            arguments: [p1]
        )
    }
    static var historyRecoveryCopy: String {
        VyronResourceBundle.string("statusHistoryRecoveryCopy", fallback: "Your previous history could not be read. A recovery copy has been kept alongside your conversation history.")
    }
    static var historyRenameUnavailable: String {
        VyronResourceBundle.string("statusHistoryRenameUnavailable", fallback: "The chat could not be renamed while conversation history needs recovery.")
    }
    static func historySaveFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusHistorySaveFailed",
            fallback: "Conversation could not be saved. %@",
            arguments: [p1]
        )
    }
    static var historyUnavailable: String {
        VyronResourceBundle.string("statusHistoryUnavailable", fallback: "History could not be read or backed up. New chats will stay in memory to preserve the original file.")
    }
    static var importBusy: String {
        VyronResourceBundle.string("statusImportBusy", fallback: "Select On this Mac and finish the current task or download before importing a model.")
    }
    static var importCanceled: String {
        VyronResourceBundle.string("statusImportCanceled", fallback: "Model import canceled. Choose the variant again to restart.")
    }
    static var inspectingProject: String {
        VyronResourceBundle.string("statusInspectingProject", fallback: "Inspecting the project")
    }
    static var interruptedOnClose: String {
        VyronResourceBundle.string("statusInterruptedOnClose", fallback: "Interrupted when Vyron closed")
    }
    static var lastCommandFailed: String {
        VyronResourceBundle.string("statusLastCommandFailed", fallback: "last command failed")
    }
    static var lastCommandPassed: String {
        VyronResourceBundle.string("statusLastCommandPassed", fallback: "last command passed")
    }
    static var lastCommandTimedOut: String {
        VyronResourceBundle.string("statusLastCommandTimedOut", fallback: "last command timed out")
    }
    static var latestCheckFailed: String {
        VyronResourceBundle.string("statusLatestCheckFailed", fallback: "latest check failed")
    }
    static var latestCheckPassed: String {
        VyronResourceBundle.string("statusLatestCheckPassed", fallback: "latest check passed")
    }
    static var latestCheckTimedOut: String {
        VyronResourceBundle.string("statusLatestCheckTimedOut", fallback: "latest check timed out")
    }
    static var loading: String {
        VyronResourceBundle.string("statusLoading", fallback: "Loading…")
    }
    static var localServer: String {
        VyronResourceBundle.string("statusLocalServer", fallback: "Local server")
    }
    static var localSettingsSaved: String {
        VyronResourceBundle.string("statusLocalSettingsSaved", fallback: "Saved settings for models on this Mac.")
    }
    static func maximumAttachedFiles(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "statusMaximumAttachedFiles",
            fallback: "Include up to %d files in one conversation.",
            arguments: [p1]
        )
    }
    static var messageTooLong: String {
        VyronResourceBundle.string("statusMessageTooLong", fallback: "This message is too long for the local context window. Keep it under 12 KB, or include a selected project file instead.")
    }
    static var modelChangeBusy: String {
        VyronResourceBundle.string("statusModelChangeBusy", fallback: "Finish or stop the current task before changing models.")
    }
    static func modelImported(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusModelImported",
            fallback: "Imported %@. Select it in the model picker.",
            arguments: [p1]
        )
    }
    static func modelNameExists(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusModelNameExists",
            fallback: "A model named %@ is already installed. Choose another local name.",
            arguments: [p1]
        )
    }
    static func modelReady(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusModelReady",
            fallback: "%@ is ready on this Mac.",
            arguments: [p1]
        )
    }
    static var noAutomaticModel: String {
        VyronResourceBundle.string("statusNoAutomaticModel", fallback: "No installed model is eligible for Auto. Download a coding option, or use an installed model with manual selection.")
    }
    static var openingProject: String {
        VyronResourceBundle.string("statusOpeningProject", fallback: "Opening project…")
    }
    static var openProjectForEdits: String {
        VyronResourceBundle.string("statusOpenProjectForEdits", fallback: "Open this project to enable local edits.")
    }
    static var pauseDownloadFirst: String {
        VyronResourceBundle.string("statusPauseDownloadFirst", fallback: "Pause the active download before starting another model.")
    }
    static var planReady: String {
        VyronResourceBundle.string("statusPlanReady", fallback: "Plan ready")
    }
    static var planReadyReadOnly: String {
        VyronResourceBundle.string("statusPlanReadyReadOnly", fallback: "Plan ready · Read-only")
    }
}
