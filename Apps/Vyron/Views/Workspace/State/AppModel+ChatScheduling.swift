import Foundation
import VyronCore

extension AppModel {
    /// Builds an editor draft only. Saving or executing a scheduled task remains an explicit editor action.
    func chatSchedulingTemplate(for id: UUID) -> VyronChatSchedulingTemplate? {
        guard chatActions(for: id) != nil, canPrepareChatSchedule(id),
            let conversation = conversations.first(where: { $0.id == id }),
            let prompt = chatSchedulingPrompt(conversation),
            let context = chatSchedulingContext(for: conversation)
        else { return nil }
        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let definition = VyronScheduledTaskDefinition(
            title: String((title.isEmpty ? prompt : title).prefix(VyronScheduledTaskLimits.titleCharacters)),
            prompt: prompt,
            context: context
        )
        return VyronChatSchedulingTemplate(conversationID: id, definition: definition)
    }

    private func canPrepareChatSchedule(_ id: UUID) -> Bool {
        (selectedConversationID != id || isConversationModeCompatible(composer.mode))
            && canTransitionForegroundConversation
            && !isSideChatGenerating(id) && !isSidebarConversationActive(id)
            && (conversations.first { $0.id == id }?.queuedMessages ?? []).isEmpty
            && !workspaceState.isLoadingWorkspace && !modelSelection.connectionOperationInProgress
            && !modelSelection.isStarting && !modelDownloads.isActive
            && !modelSelection.isRefreshing && !composer.isEditingQueuedMessage
            && !voice.isActive && !composerAttachments.isImporting
    }

    private func chatSchedulingContext(for conversation: Conversation) -> VyronScheduledTaskContext? {
        let selectedContext = scheduledTaskContext()
        if selectedConversationID == conversation.id {
            guard schedulingURL(selectedContext.workspacePath) == schedulingURL(conversation.workspacePath),
                schedulingURL(selectedContext.projectPath) == schedulingURL(conversation.sidebarProjectPath),
                selectedContext.mode == .chat || chatSchedulingWorkspaceMatches
            else { return nil }
            return selectedContext
        }
        let mode: VyronScheduledTaskMode
        switch conversation.mode.flatMap(ComposerMode.init(rawValue:)) ?? .agent {
        case .agent: mode = .agent
        case .plan: mode = .plan
        case .chat: mode = .chat
        }
        if let path = conversation.workspacePath {
            guard path.hasPrefix("/"),
                !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { return nil }
            let source = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            if let project = conversation.sidebarProjectPath,
                sidebarState.sidebarOrganization.contains(.project(project)),
                !sidebarProjectSourceFolders(project).contains(source.path) { return nil }
            do {
                // A menu draft must not adopt the selected chat's project or an unavailable source folder.
                _ = try ProjectWorkspace(rootURL: source)
            } catch {
                return nil
            }
        } else if mode != .chat {
            return nil
        }
        return VyronScheduledTaskContext(
            workspacePath: conversation.workspacePath,
            mode: mode,
            model: selectedContext.model,
            projectPath: conversation.sidebarProjectPath
        )
    }

    private func chatSchedulingPrompt(_ conversation: Conversation) -> String? {
        let ownership = VyronConversationResponseOwnership(messages: conversation.messages)
        var originalGoal: String?
        var guidance: [String] = []
        var isUserGroup = false
        var latestTurnGoal: String?
        var latestUserIndex: Int?
        for (index, message) in conversation.messages.enumerated() {
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let isContinuation = VyronDevelopmentContinuationContext.isContinuationRequest(text)
            if ownership.isChild(message) {
                if message.conversationRole == .user, originalGoal != nil, !text.isEmpty, !isContinuation {
                    guidance.append(text)
                }
                continue
            }
            if message.conversationRole == .user {
                if !isUserGroup { latestTurnGoal = text }
                latestUserIndex = index
                if !isUserGroup, !isContinuation {
                    originalGoal = text.isEmpty ? nil : text
                    guidance.removeAll(keepingCapacity: true)
                } else if isUserGroup, !text.isEmpty, !isContinuation {
                    guidance.append(text)
                }
                isUserGroup = true
            } else {
                isUserGroup = false
            }
        }
        if let latestTurnGoal, let latestUserIndex,
            VyronDevelopmentContinuationContext.isContinuationRequest(latestTurnGoal) {
            guard let continuation = VyronDevelopmentContinuationHistory.context(
                for: latestTurnGoal,
                messages: Array(conversation.messages.prefix(latestUserIndex + 1))
            ) else { return nil }
            originalGoal = continuation.originalGoal
        }
        guard let originalGoal else { return nil }
        return ([originalGoal] + guidance).joined(separator: "\n\n")
    }

    private func schedulingURL(_ path: String?) -> URL? {
        path.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
    }
}
