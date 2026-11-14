extension AppModel {
    var workspaceToolAvailability: VyronWorkspaceToolAvailability {
        let sideChatID = selectedConversationID.flatMap { id in
            canCreateSideChat(from: id) ? id : nil
        }
        return VyronWorkspaceToolAvailability(
            projectToolsEnabled: !isChatWorkspace && !isShuttingDown,
            sideChatConversationID: sideChatID
        )
    }

    func openWorkspaceTool(_ tool: VyronWorkspaceTool) {
        guard workspaceToolAvailability.projectToolsEnabled else { return }
        switch tool {
        case .changes:
            appNavigation.trackingSelection = nil
            inspector.closeResponseChangeReview()
            inspector.inspectorTab = .changes
            appNavigation.showWorkspace = true
        case .files:
            appNavigation.trackingSelection = nil
            inspector.inspectorTab = .files
            appNavigation.showWorkspace = true
        case .terminal:
            inspector.showTerminal.toggle()
        }
    }
}
