import VyronCore

extension DevelopmentEvent {
    var localizedMessage: String {
        if isTaskCheckpointFailure { return VyronStatusText.taskCheckpointUnavailable }
        if let projectItemMessage = localizedProjectItemMessage { return projectItemMessage }
        if tool == "create_folder" {
            switch kind {
            case .toolStarted: return VyronFolderText.creating
            case .toolFinished where failure == nil: return VyronFolderText.ready
            default: return message
            }
        }
        if isProjectFolderOpening {
            switch kind {
            case .toolStarted: return VyronHandoffText.opening
            case .toolFinished where failure == nil: return VyronFolderText.ready
            default: return message
            }
        }
        if isParallelTask {
            switch kind {
            case .toolStarted:
                return VyronTrackingText.parallelStarted
            case .toolFinished where failure == nil:
                return VyronTrackingText.parallelFinished
            default:
                return message
            }
        }
        guard isUserInput else { return message }
        switch kind {
        case .toolStarted:
            return VyronQuestionText.waitingForAnswer
        case .toolFinished where failure == nil:
            return VyronQuestionText.answerReceived
        default:
            return message
        }
    }

    private var localizedProjectItemMessage: String? {
        guard let tool, failure == nil else { return nil }
        switch (tool, kind) {
        case ("move_item", .toolStarted): return VyronProjectItemText.moving
        case ("move_item", .toolFinished), ("move_item", .fileChanged): return VyronProjectItemText.moved
        case ("rename_item", .toolStarted): return VyronProjectItemText.renaming
        case ("rename_item", .toolFinished), ("rename_item", .fileChanged): return VyronProjectItemText.renamed
        case ("trash_item", .toolStarted): return VyronProjectItemText.trashing
        case ("trash_item", .toolFinished), ("trash_item", .fileChanged): return VyronProjectItemText.trashed
        default: return nil
        }
    }
}
