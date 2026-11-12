extension DevelopmentEvent {
    public var isProjectFolderOpening: Bool { tool == VyronDevelopmentToolName.openProjectFolder }

    public var activityCategory: VyronActivityCategory {
        if isUserInput { return .question }
        if isParallelTask { return .agents }
        if isProjectFolderOpening { return .files }
        switch tool {
        case "list_files", "create_folder": return .files
        case "read_file": return .read
        case "search": return .search
        case "edit_file", "write_file", "move_item", "rename_item", "trash_item": return .edit
        case "run_command": return .command
        case .some: return .integration
        case .none:
            switch kind {
            case .commandStarted, .commandOutput, .commandFinished: return .command
            case .fileChanged: return .edit
            default: return .general
            }
        }
    }

    public var activityContent: VyronActivityContent? {
        let entryKind: ResponseActivity.Entry.Kind
        let detail: String?
        switch kind {
        case .assistant:
            entryKind = .explanation
            detail = content ?? message
        case .status:
            entryKind = .status
            detail = [content, command].compactMap { $0 }.joined(separator: "\n")
        case .toolStarted:
            entryKind = .tool
            detail = command ?? content ?? path
        case .fileChanged, .commandStarted, .commandFinished:
            entryKind = .tool
            detail = command ?? path
        case .toolFinished:
            entryKind = .tool
            // Successful file output belongs to model context, never activity history.
            detail = failure ?? command ?? path
        case .commandOutput:
            return nil
        }
        return VyronActivityContent(kind: entryKind, title: message, detail: detail, category: activityCategory)
    }
}
