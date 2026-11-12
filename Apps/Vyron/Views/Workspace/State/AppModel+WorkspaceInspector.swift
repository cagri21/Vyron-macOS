import Foundation

extension AppModel {
    var isWorkspaceInspectorVisible: Bool {
        appNavigation.trackingSelection != nil || (!isChatWorkspace && appNavigation.showWorkspace)
    }

    var canToggleWorkspaceInspector: Bool {
        appNavigation.trackingSelection != nil || !isChatWorkspace
    }

    func toggleWorkspaceInspector() {
        if appNavigation.trackingSelection != nil {
            closeActivity()
            appNavigation.showWorkspace = false
        } else if !isChatWorkspace {
            appNavigation.showWorkspace.toggle()
        }
    }
}
