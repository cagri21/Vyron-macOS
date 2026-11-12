import Foundation
import VyronAutomation
import VyronCore

extension AppModel {
    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    var messages: [ChatMessage] { selectedConversation?.messages ?? [] }

    var canSend: Bool {
        if composer.isEditingQueuedMessage {
            return !isShuttingDown && !composer.trimmedDraft.isEmpty
        }
        if VyronConversationCompactionCommand(prompt: composer.draft) != nil { return canAcceptCompactionCommand }
        return canAcceptConversationMessage
            && (!composer.trimmedDraft.isEmpty || composerAttachments.hasDrafts)
    }
    var canAcceptConversationMessage: Bool {
        canAcceptConversationMessage(in: composer.mode)
    }

    var canMoveConversationToProject: Bool {
        composer.mode == .agent && workspaceState.developmentWorkspace != nil && !isRunningScheduledTask
    }

    var canTransitionForegroundConversation: Bool {
        foregroundRun.isIdle && computerWork.isIdle && !isRunningScheduledTask && scheduledTasks.activeTaskID == nil
            && interactions.pendingUserInput == nil
    }

    func canAcceptConversationMessage(in mode: ComposerMode) -> Bool {
        !isShuttingDown && !isSideChatGenerating(selectedConversationID)
            && !modelSelection.connectionOperationInProgress && modelSelection.inferenceProvider != nil
            && isConversationModeCompatible(mode)
            && isComposerModeAvailable(mode) && canRunInSelectedConversation(mode)
            && scheduledTasks.activeTaskID == nil
            && !modelDownloads.isActive
            && (mode != .agent || (workspaceState.developmentWorkspace != nil && selectedProjectBindingMatches))
            && !computerWork.isComputerWorkActive && !computerWork.isPlanningControls
            && modelSelection.isConnected && modelSelection.modelIsAvailable
            && (!foregroundRun.isGenerating || canAcceptFollowUp)
            && (mode == .chat || workspaceState.workspaceURL == nil || selectedProjectSourceFolderIsAttached)
            && composerAttachments.pendingAttachments.isEmpty
            && !workspaceState.isLoadingWorkspace && !composerAttachments.isImporting
            && (!composerAttachments.hasDrafts || !foregroundRun.isGenerating)
    }

    func canRunInSelectedConversation(_ mode: ComposerMode) -> Bool {
        guard mode != .chat, workspaceState.workspaceURL != nil else { return true }
        if foregroundRun.isStoppingDevelopment { return false }
        if let work = foregroundRun.developmentResponse { return work.conversationID == selectedConversationID }
        return true
    }

    func requestNewTask(projectPath: String? = nil) {
        guard !isShuttingDown else { return }
        if let projectPath {
            newSidebarProjectConversation(projectPath)
        } else {
            newConversation()
        }
    }

    func requestSidebarConversation(_ id: UUID) {
        guard !isShuttingDown else { return }
        selectConversation(id)
    }

    func newConversation() {
        appNavigation.destination = .workspace
        leaveForegroundConversation()
        composer.cancelQueuedMessageEdit()
        selectedConversationID = nil
        inspector.showDevelopmentOutput(for: nil)
        composer.draft = ""
        errorMessage = nil
        statusMessage = nil
        composerAttachments.attachedFiles = []
        resetPendingAttachments()
        workspaceState.isLoadingWorkspace = false
        forceConversationNextSend = false
        composer.mode = foregroundRun.hasBackgroundResponses || foregroundRun.isStoppingDevelopment ? .chat : .agent
        if workspaceState.developmentWorkspace == nil, workspaceState.workspaceURL != nil {
            statusMessage = VyronStatusText.openProjectForEdits
        }
    }

    func selectConversation(_ id: UUID, loadProject: Bool = true) {
        appNavigation.destination = .workspace
        guard markChatRead(id) else { return }
        guard selectedConversationID != id else { return }
        leaveForegroundConversation()
        composer.cancelQueuedMessageEdit()
        selectedConversationID = id
        inspector.showDevelopmentOutput(for: id)
        composer.mode = restoredConversationMode
        composer.draft = ""
        errorMessage = nil
        statusMessage = nil
        composerAttachments.attachedFiles = []
        resetPendingAttachments()
        forceConversationNextSend = false
        foregroundRun.bringResponseToForeground(in: id)
        composer.pendingSteeringIDs = foregroundRun.activePendingSteeringIDs
        let path = selectedConversation?.workspacePath
        let projectPath = selectedConversation?.sidebarProjectPath
        if let path, let projectPath, sidebarState.sidebarOrganization.contains(.project(projectPath)),
            !sidebarProjectSourceFolders(projectPath).contains(URL(fileURLWithPath: path).standardizedFileURL.path) {
            clearWorkspace()
            workspaceState.selectedProjectPath = projectPath
            statusMessage = VyronSidebarText.sourceFolderRemoved
            return
        }
        workspaceState.selectedProjectPath = projectPath
        if loadProject && (
            path != workspaceState.workspaceURL?.path || (path != nil && workspaceState.developmentWorkspace == nil)
        ) {
            if let path {
                let selectionID = prepareWorkspaceSelection(
                    URL(fileURLWithPath: path, isDirectory: true), projectPath: projectPath
                )
                Task {
                    await loadWorkspace(
                        URL(fileURLWithPath: path, isDirectory: true),
                        expectedConversationID: id,
                        expectedSelectionID: selectionID,
                        projectPath: projectPath
                    )
                }
            } else {
                clearWorkspace()
            }
        } else if loadProject, composer.mode != .chat, path != nil {
            refreshProject()
        }
    }

    func activateChatHandoff(_ id: UUID) async -> Bool {
        guard !Task.isCancelled, !isShuttingDown, !foregroundRun.isGenerating, !foregroundRun.isDeveloping,
            !foregroundRun.isStoppingDevelopment, !computerWork.isComputerWorkActive, !computerWork.isPlanningControls,
            !isRunningScheduledTask, scheduledTasks.activeTaskID == nil,
            composerAttachments.pendingAttachments.isEmpty,
            let conversation = conversations.first(where: { $0.id == id }),
            !sidebarState.sidebarOrganization.isConversationArchived(id),
            let path = conversation.workspacePath, let projectPath = conversation.sidebarProjectPath,
            sidebarState.sidebarOrganization.contains(.project(projectPath)),
            sidebarProjectSourceFolders(projectPath).contains(path)
        else { return false }
        selectConversation(id, loadProject: false)
        guard selectedConversationID == id else { return false }
        let targetURL = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
        if workspaceState.workspaceURL?.resolvingSymlinksInPath() != targetURL
            || workspaceState.developmentWorkspace == nil {
            await loadWorkspace(targetURL, expectedConversationID: id, projectPath: projectPath)
        }
        return !Task.isCancelled && !isShuttingDown && selectedConversationID == id
            && !workspaceState.isLoadingWorkspace && workspaceState.workspaceURL?.resolvingSymlinksInPath() == targetURL
            && workspaceState.developmentWorkspace != nil && workspaceState.selectedProjectPath == projectPath
            && errorMessage == nil
    }

    func deleteConversation(_ id: UUID) {
        guard foregroundRun.response(in: id) == nil else { return }
        guard !isSideChatGenerating(id) else {
            errorMessage = VyronHeaderText.sideChatRunning
            return
        }
        if let taskID = scheduledTasks.activeTaskID,
            scheduledTasks.tasks.first(where: { $0.id == taskID })?.progress.lastRun?.output.conversationID == id {
            errorMessage = VyronScheduledTaskText.activeTaskLocked
            return
        }
        let previous = conversations
        conversations.removeAll { $0.id == id }
        guard saveHistory() else {
            conversations = previous
            if errorMessage == nil {
                errorMessage = VyronStatusText.historyDeleteUnavailable
            }
            return
        }
        if selectedConversationID == id { newConversation() }
        newSideChatSessions.removeValue(forKey: id)
        removeSidebarConversation(id)
    }

    func usePrompt(_ prompt: String) {
        forceConversationNextSend = false
        composer.draft = prompt
    }

    func useSuggestedQuestion(_ question: String, messageID: UUID) {
        guard !foregroundRun.isGenerating, !computerWork.isComputerWorkActive, !isShuttingDown,
            composer.trimmedDraft.isEmpty,
            let answer = messages.last, answer.id == messageID,
            answer.conversationRole == .assistant, answer.activity?.state == .completed,
            answer.suggestedQuestions?.contains(question) == true
        else { return }
        usePrompt(question)
    }

    func discussSnapshot(_ snapshot: AutomationSnapshot) {
        if !isConversationModeCompatible(.chat) { newConversation() }
        composer.mode = .chat
        let excerpt = VyronConversationRequestContext.bytePrefix(snapshot.text, limit: 8_000)
        let truncated = excerpt != snapshot.text ? "\n[snapshot excerpt truncated]" : ""
        composer.draft =
            "Help me understand this read-only snapshot of \(snapshot.applicationName), captured at \(snapshot.capturedAt.formatted(date: .omitted, time: .shortened)). Do not perform any actions.\n\n<app-snapshot>\n\(excerpt)\(truncated)\n</app-snapshot>"
        forceConversationNextSend = true
        statusMessage = VyronStatusText.snapshotReadOnly
        appNavigation.showAutomation = false
    }

    @discardableResult
    func saveHistory() -> Bool {
        guard historyIsWritable else { return false }
        do {
            try historyStore.save(conversations)
            notificationDidSaveHistory()
            return true
        } catch {
            errorMessage = VyronStatusText.historySaveFailed(error.localizedDescription)
            return false
        }
    }

    func saveRenamedSidebarConversation() -> Bool {
        guard historyIsWritable else {
            errorMessage = VyronStatusText.historyRenameUnavailable
            return false
        }
        return saveHistory()
    }
}
