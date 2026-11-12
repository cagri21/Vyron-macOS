import Foundation
import VyronDevelopment

extension AppModel {
    var taskOverview: VyronTaskOverviewSnapshot {
        let selected = selectedConversation
        let path = selected == nil ? workspaceState.workspaceURL?.path : selected?.workspacePath
        let matchesWorkspace = !isChatWorkspace && path != nil && path == workspaceState.workspaceURL?.path
        return VyronTaskOverviewSnapshot(
            conversation: selected,
            project: VyronTaskOverviewProject(
                path: matchesWorkspace ? path : nil,
                changes: matchesWorkspace ? inspector.developmentChanges : []
            )
        )
    }

    func openOverviewInspector(_ tab: ProjectInspectorTab, context: VyronTaskOverviewSnapshot) {
        guard context.conversationID == selectedConversationID,
            context.project.path != nil, context.project.path == workspaceState.workspaceURL?.path,
            !isChatWorkspace
        else { return }
        appNavigation.trackingSelection = nil
        inspector.inspectorTab = tab
        appNavigation.showWorkspace = true
    }

    func openOverviewOutput(_ path: String, context: VyronTaskOverviewSnapshot) {
        guard context.conversationID == selectedConversationID,
            context.project.path == workspaceState.workspaceURL?.path,
            context.project.path != nil, !isChatWorkspace,
            inspector.developmentChanges.contains(where: { $0.path == path })
        else { return }
        if let file = inspector.developmentFiles.first(where: { $0.path == path }) {
            openOverviewInspector(.files, context: context)
            openProjectFile(file)
        } else {
            // A just-created output can precede the next file inventory refresh.
            openOverviewInspector(.changes, context: context)
            inspector.selectedChangePath = path
        }
    }

    func openOverviewActivity(_ context: VyronTaskOverviewSnapshot, subagentID: UUID? = nil) {
        guard let conversationID = context.conversationID,
            conversationID == selectedConversationID, let response = context.response
        else { return }
        openActivity(conversationID: conversationID, messageID: response.id, subagentID: subagentID)
    }
}
