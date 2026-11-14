import Foundation
import VyronDevelopment

extension AppModel {
    var isWorkspaceInspectorVisible: Bool {
        appNavigation.trackingSelection != nil || (canToggleWorkspaceInspector && appNavigation.showWorkspace)
    }

    var canToggleWorkspaceInspector: Bool {
        appNavigation.trackingSelection != nil || !isChatWorkspace || inspector.responseChangeReview != nil
    }

    func toggleWorkspaceInspector() {
        if appNavigation.trackingSelection != nil {
            closeActivity()
            appNavigation.showWorkspace = false
        } else if canToggleWorkspaceInspector {
            appNavigation.showWorkspace.toggle()
        }
    }

    func showChangeReview(
        conversationID: UUID,
        workspacePath: String,
        changes: [DevelopmentChange],
        selectedPath: String?
    ) {
        guard conversationID == selectedConversationID, !changes.isEmpty else { return }
        closeActivity()
        inspector.openResponseChangeReview(VyronInspectorChangeReview(
            conversationID: conversationID,
            workspacePath: workspacePath,
            changes: changes,
            selectedPath: selectedPath
        ))
        appNavigation.showWorkspace = true
    }
}
