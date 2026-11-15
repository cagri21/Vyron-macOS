import Foundation

extension AppModel {
    @discardableResult
    func openNotification(_ item: VyronNotificationItem) -> Bool {
        guard !isShuttingDown, notificationItems.contains(where: { $0.id == item.id }) else { return false }
        switch item.id.target {
        case .response(let response):
            guard canOpenSideChatInMain(response.conversationID)
                || (item.kind.isAttention && canOpenTaskAttention(response)) else { return false }
            if selectedConversationID != response.conversationID { selectConversation(response.conversationID) }
            guard selectedConversationID == response.conversationID else { return false }
            appNavigation.destination = .workspace
            if !item.kind.isAttention {
                openActivity(conversationID: response.conversationID, messageID: response.responseID)
            }
        case .scheduledRun(let target):
            guard scheduledTasks.tasks.contains(where: {
                $0.id == target.taskID && $0.progress.lastRun?.id == target.runID
            }) else { return false }
            appNavigation.showScheduledTasks = true
        case .plugins:
            guard !voice.isActive else { return false }
            openPlugins()
        }
        markNotificationRead(item.id)
        return true
    }

    private func canOpenTaskAttention(_ response: VyronNotificationResponseID) -> Bool {
        guard let owner = foregroundRun.response(in: response.conversationID), owner.messageID == response.responseID,
            foregroundRun.isDevelopmentResponse(owner) || mcpConnections.pendingReview?.responseOwner == response
        else { return false }
        return (!foregroundRun.isGenerating || foregroundRun.canContinueInBackground)
            && computerWork.isIdle && !voice.isActive && !isRunningScheduledTask && scheduledTasks.activeTaskID == nil
            && !composer.isEditingQueuedMessage && composer.pendingSteeringIDs.isEmpty
            && (selectedConversation?.queuedMessages ?? []).isEmpty
            && composer.trimmedDraft.isEmpty && composerAttachments.attachedFiles.isEmpty
            && composerAttachments.pendingAttachments.isEmpty && !composerAttachments.hasDrafts
            && !composerAttachments.isImporting && !workspaceState.isLoadingWorkspace
    }

    /// A busy or dirty main composer can stay in place while the requested transcript opens read-only.
    func notificationWindowTarget(_ item: VyronNotificationItem) -> UUID? {
        guard !isShuttingDown, notificationItems.contains(where: { $0.id == item.id }),
            let id = item.conversationID, conversations.contains(where: { $0.id == id }) else { return nil }
        markNotificationRead(item.id)
        return id
    }
}
