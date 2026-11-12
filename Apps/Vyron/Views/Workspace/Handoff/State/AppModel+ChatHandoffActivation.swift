import Foundation

extension AppModel {
    func prepareChatHandoffSend(destinationID: UUID, request: String) {
        guard selectedConversationID == destinationID, composer.draft == request else { return }
        handoff.preparedChatHandoffDraft = VyronPreparedChatHandoffDraft(destinationID: destinationID, request: request)
    }

    /// Opening the chooser does not consume a prompt, switch projects, or start a model request.
    func routeChatHandoffIfRequested() -> Bool {
        guard !isShuttingDown, !foregroundRun.isGenerating, !foregroundRun.isDeveloping,
            !foregroundRun.isStoppingDevelopment, !computerWork.isPlanningControls,
            !computerWork.isComputerWorkActive, !isRunningScheduledTask, !composer.isEditingQueuedMessage,
            interactions.pendingUserInput == nil, computerWork.pendingAgentGoal == nil,
            scheduledTasks.activeTaskID == nil, !workspaceState.isLoadingWorkspace,
            composerAttachments.attachedFiles.isEmpty, !composerAttachments.hasDrafts, !composerAttachments.isImporting,
            let id = selectedConversationID,
            !sidebarState.sidebarOrganization.isConversationArchived(id),
            (selectedConversation?.queuedMessages ?? []).isEmpty
        else { return false }
        let prompt = composer.trimmedDraft
        if let preparedChatHandoffDraft = handoff.preparedChatHandoffDraft,
            preparedChatHandoffDraft.destinationID == id, preparedChatHandoffDraft.request == prompt {
            return false
        }
        guard let intent = chatHandoffIntent(for: prompt) else { return false }
        if canMoveConversationToProject, intent.movesConversation { return false }
        guard intent.projectPath == nil || intent.projectPath != selectedConversation?.sidebarProjectPath else {
            return false
        }
        let selection = intent.projectPath.flatMap { path -> VyronChatHandoffSelection? in
            guard let source = sidebarProjectSourceFolders(path).first else { return nil }
            return VyronChatHandoffSelection(projectPath: path, workspacePath: source)
        }
        handoff.chatHandoffPresentation = VyronChatHandoffPresentation(
            sourceID: id, initialRequest: intent.request, destination: selection,
            requiresDestinationSelection: intent.projectPath == nil
        )
        return true
    }

    func conversationMoveDestination(for prompt: String) -> VyronChatHandoffSelection? {
        guard canMoveConversationToProject, let intent = chatHandoffIntent(for: prompt), intent.movesConversation,
            let projectPath = intent.projectPath,
            let folder = chatHandoffSourceFolders(for: projectPath).first else { return nil }
        return VyronChatHandoffSelection(projectPath: projectPath, workspacePath: folder)
    }

    private func chatHandoffIntent(for prompt: String) -> VyronChatHandoffIntent? {
        let projects = Dictionary(uniqueKeysWithValues: sidebarState.sidebarOrganization.allProjects.map {
            ($0, sidebarProjectName($0))
        })
        return VyronChatHandoffIntent(prompt: prompt, projects: projects)
    }
}
