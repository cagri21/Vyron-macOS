import Foundation

extension AppModel {
    func handOffChat(_ request: VyronChatHandoffRequest) async -> Bool {
        let previousSelectionID = selectedConversationID
        let previousWorkspaceURL = workspaceState.workspaceURL
        let previousProjectPath = workspaceState.selectedProjectPath
        let previousMode = composer.mode
        let sourceDraft = composer.draft
        guard let transaction = prepareChatHandoff(request) else { return false }
        let id = transaction.destination.id
        guard await activateChatHandoff(id), !Task.isCancelled,
            selectedConversationID == id,
            let current = conversations.first(where: { $0.id == id }),
            current.messages == transaction.destination.messages,
            current.workspacePath == transaction.destination.workspacePath,
            current.sidebarProjectPath == request.destination.projectPath,
            !sidebarState.sidebarOrganization.isConversationArchived(id), !isSidebarConversationActive(id),
            (current.queuedMessages ?? []).isEmpty else {
            let failure = errorMessage ?? VyronHandoffText.unavailable
            restorePreparedChatHandoff(transaction)
            if selectedConversationID == id {
                if let previousSelectionID {
                    selectConversation(previousSelectionID)
                } else {
                    newConversation()
                    clearWorkspace()
                    if let previousWorkspaceURL {
                        await loadWorkspace(previousWorkspaceURL, projectPath: previousProjectPath)
                    }
                    if selectedConversationID == nil {
                        workspaceState.selectedProjectPath = previousProjectPath
                        composer.mode = previousMode
                    }
                }
                if selectedConversationID == previousSelectionID { composer.draft = sourceDraft }
            }
            errorMessage = failure
            return false
        }
        composer.draft = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        prepareChatHandoffSend(destinationID: id, request: composer.draft)
        return true
    }

    /// Roll back only the exact prepared snapshot; another window's later edits must remain intact.
    func restorePreparedChatHandoff(_ transaction: VyronChatHandoffTransaction) {
        let id = transaction.destination.id
        guard let index = conversations.firstIndex(where: { $0.id == id }),
            transaction.matches(conversations[index]) else { return }
        if let previous = transaction.previousDestination {
            conversations[index] = previous
        } else {
            conversations.remove(at: index)
            // Remove only this new chat registration, preserving concurrent sidebar changes.
            changeSidebar { $0.removeItem(.conversation(id)) }
        }
        saveHistory()
    }
}
