// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronStatusText {
    static var preparingContext: String {
        VyronResourceBundle.string("statusPreparingContext", fallback: "Preparing conversation context")
    }
    static var preparingRequest: String {
        VyronResourceBundle.string("statusPreparingRequest", fallback: "Preparing the request")
    }
    static var projectUnavailable: String {
        VyronResourceBundle.string("statusProjectUnavailable", fallback: "Project unavailable · Open it again or choose another project.")
    }
    static var remoteServer: String {
        VyronResourceBundle.string("statusRemoteServer", fallback: "Remote server")
    }
    static func replyReady(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusReplyReady",
            fallback: "Reply ready · %@",
            arguments: [p1]
        )
    }
    static func requestContext(_ p1: String, _ p2: String, _ p3: String) -> String {
        VyronResourceBundle.format(
            "statusRequestContext",
            fallback: "%@ mode · %@ · %@",
            arguments: [p1, p2, p3]
        )
    }
    static var requestingResponse: String {
        VyronResourceBundle.string("statusRequestingResponse", fallback: "Requesting a response")
    }
    static var responseFailed: String {
        VyronResourceBundle.string("statusResponseFailed", fallback: "Response failed")
    }
    static func responseModel(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusResponseModel",
            fallback: "Model: %@",
            arguments: [p1]
        )
    }
    static var responseReady: String {
        VyronResourceBundle.string("statusResponseReady", fallback: "Response ready")
    }
    static var responseStopped: String {
        VyronResourceBundle.string("statusResponseStopped", fallback: "Response stopped")
    }
    static var responseStoppedSaved: String {
        VyronResourceBundle.string("statusResponseStoppedSaved", fallback: "Response stopped. Any partial reply has been saved.")
    }
    static func revertedFile(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusRevertedFile",
            fallback: "Reverted %@.",
            arguments: [p1]
        )
    }
    static func savedConnectionsUnavailable(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusSavedConnectionsUnavailable",
            fallback: "Saved model connections could not be loaded. The original file has been preserved. %@",
            arguments: [p1]
        )
    }
    static func selectedFiles(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "statusSelectedFiles",
            fallback: "Selected files: %d",
            arguments: [p1]
        )
    }
    static var selectLocalForDownload: String {
        VyronResourceBundle.string("statusSelectLocalForDownload", fallback: "Select On this Mac before downloading local model weights.")
    }
    static var snapshotReadOnly: String {
        VyronResourceBundle.string("statusSnapshotReadOnly", fallback: "This snapshot will be discussed without taking computer actions.")
    }
    static var startEngineForDownload: String {
        VyronResourceBundle.string("statusStartEngineForDownload", fallback: "Start the local engine before downloading a model.")
    }
    static var startingEngine: String {
        VyronResourceBundle.string("statusStartingEngine", fallback: "Starting local engine")
    }
    static var startOllama: String {
        VyronResourceBundle.string("statusStartOllama", fallback: "Start Ollama to connect your local models.")
    }
    static var stoppedByYou: String {
        VyronResourceBundle.string("statusStoppedByYou", fallback: "Stopped by you")
    }
    static var stoppedOnQuit: String {
        VyronResourceBundle.string("statusStoppedOnQuit", fallback: "Stopped when Vyron quit")
    }
    static var stoppedWithError: String {
        VyronResourceBundle.string("statusStoppedWithError", fallback: "Stopped · See error details")
    }
    static var stoppingDevelopment: String {
        VyronResourceBundle.string("statusStoppingDevelopment", fallback: "Stopping the development task and its commands…")
    }
    static var taskCheckpointUnavailable: String {
        VyronResourceBundle.string("statusTaskCheckpointUnavailable", fallback: "Task progress could not be saved")
    }
    static func usingConnection(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "statusUsingConnection",
            fallback: "Using %@ · %@",
            arguments: [p1, p2]
        )
    }
    static func usingManualChatModel(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusUsingManualChatModel",
            fallback: "Using %@ for chat · Manual selection",
            arguments: [p1]
        )
    }
    static func usingManualModel(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusUsingManualModel",
            fallback: "Using %@ · Manual selection",
            arguments: [p1]
        )
    }
    static func workspaceOpenFailure(_ p1: String) -> String {
        VyronResourceBundle.format(
            "statusWorkspaceOpenFailure",
            fallback: "Workspace could not be opened. %@",
            arguments: [p1]
        )
    }
    static var writingResponse: String {
        VyronResourceBundle.string("statusWritingResponse", fallback: "Writing the response")
    }
}
