import Foundation
import VyronCore

extension AppModel {
    func presentChatHandoff(from id: UUID) {
        guard chatActions(for: id)?.canContinue == true else { return }
        handoff.chatHandoffPresentation = VyronChatHandoffPresentation(sourceID: id)
    }

    var chatHandoffProjects: [String] {
        sidebarState.sidebarOrganization.allProjects.filter { !chatHandoffSourceFolders(for: $0).isEmpty }
    }

    func chatHandoffSourceFolders(for projectPath: String) -> [String] {
        guard sidebarState.sidebarOrganization.contains(.project(projectPath)) else { return [] }
        return sidebarProjectSourceFolders(projectPath).filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    func chatHandoffConversations(for selection: VyronChatHandoffSelection) -> [Conversation] {
        sidebarProjectConversations(selection.projectPath).filter { conversation in
            conversation.workspacePath == selection.workspacePath
                && (conversation.mode == nil || conversation.mode == ComposerMode.agent.rawValue)
                && !sidebarState.sidebarOrganization.isConversationArchived(conversation.id)
                && !isSidebarConversationActive(conversation.id)
                && (conversation.queuedMessages ?? []).isEmpty
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func canPrepareChatHandoff(_ presentation: VyronChatHandoffPresentation) -> Bool {
        guard chatActions(for: presentation.sourceID) != nil else { return false }
        let currentDraft = composer.trimmedDraft
        let sourceDraftIsTransferred = currentDraft.isEmpty
            || (selectedConversationID == presentation.sourceID
                && currentDraft == presentation.initialRequest?.trimmingCharacters(in: .whitespacesAndNewlines))
        return sourceDraftIsTransferred
            && canTransitionForegroundConversation
            && interactions.pendingCommandApproval == nil && !isSidebarConversationActive(presentation.sourceID)
            && !composer.isEditingQueuedMessage && composer.pendingSteeringIDs.isEmpty
            && (conversations.first { $0.id == presentation.sourceID }?.queuedMessages ?? []).isEmpty
            && (selectedConversation?.queuedMessages ?? []).isEmpty
            && composerAttachments.attachedFiles.isEmpty
            && !composerAttachments.hasDrafts && !composerAttachments.isImporting
            && !workspaceState.isLoadingWorkspace && !voice.isActive
    }

    func chatHandoffDefaultRequest(for presentation: VyronChatHandoffPresentation) -> String {
        if let request = presentation.initialRequest { return request }
        return conversations.first { $0.id == presentation.sourceID }?.messages.last {
            $0.conversationRole == .user && VyronConversationCompactionCommand(prompt: $0.content) == nil
                && !VyronDevelopmentContinuationContext.isContinuationRequest($0.content)
        }?.content ?? ""
    }

    func prepareChatHandoff(_ request: VyronChatHandoffRequest) -> VyronChatHandoffTransaction? {
        guard canPrepareChatHandoff(request.source),
            let source = conversations.first(where: { $0.id == request.source.sourceID }) else {
            errorMessage = VyronHandoffText.busy
            return nil
        }
        if let failure = VyronChatHandoffContext.requestError(request.prompt) {
            errorMessage = failure
            return nil
        }
        let selection = request.destination
        guard chatHandoffProjects.contains(selection.projectPath),
            chatHandoffSourceFolders(for: selection.projectPath).contains(selection.workspacePath),
            source.sidebarProjectPath != selection.projectPath else {
            errorMessage = VyronHandoffText.unavailable
            return nil
        }
        let previous = selection.conversationID.flatMap { id in
            chatHandoffConversations(for: selection).first { $0.id == id && $0.id != source.id }
        }
        guard selection.conversationID == nil || previous != nil else {
            errorMessage = VyronHandoffText.unavailable
            return nil
        }
        var destination = previous ?? Conversation(
            title: String(request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(54)),
            workspacePath: selection.workspacePath
        )
        destination.projectPath = selection.projectPath
        destination.mode = ComposerMode.agent.rawValue
        destination.isUnread = nil
        destination.messages.append(ChatMessage(
            role: .assistant,
            content: VyronChatHandoffContext.reference(for: source)
        ))
        destination.updatedAt = Date()
        let transaction = VyronChatHandoffTransaction(
            destination: destination,
            previousDestination: previous,
            sourceID: source.id
        )
        if previous == nil, !changeSidebar({ $0.registerConversation(id: destination.id) }) { return nil }
        if let index = conversations.firstIndex(where: { $0.id == destination.id }) {
            conversations[index] = destination
        } else {
            conversations.insert(destination, at: 0)
        }
        guard saveHistory() else {
            let failure = errorMessage
            restorePreparedChatHandoff(transaction)
            errorMessage = failure ?? VyronSidebarText.saveFailure
            return nil
        }
        return transaction
    }
}
