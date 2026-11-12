import VyronCore

extension AppModel {
    var canChangeProjectApprovalMode: Bool {
        canManageModelSelection && !composer.isEditingQueuedMessage
            && !workspaceState.isLoadingWorkspace && !composerAttachments.isImporting
    }

    func selectProjectApprovalMode(_ mode: VyronProjectApprovalMode) {
        guard canChangeProjectApprovalMode else { return }
        interactions.selectProjectApprovalMode(mode)
    }
}
