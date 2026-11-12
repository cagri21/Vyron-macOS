import Foundation
import VyronCore

extension AppModel {
    func chatActions(for id: UUID) -> VyronChatActionAvailability? {
        guard !isShuttingDown,
            let conversation = conversations.first(where: { $0.id == id }),
            !sidebarState.sidebarOrganization.isConversationArchived(id) else { return nil }
        return VyronChatActionAvailability(
            conversationID: id,
            title: conversation.title,
            isPinned: sidebarState.sidebarOrganization.isPinned(.conversation(id)),
            navigation: VyronChatActionNavigationAvailability(
                canContinue: canNavigateFromChat(id),
                canArchive: selectedConversationID == id ? canNavigateFromChat(id) : canArchiveUnselectedChat(id)
            )
        )
    }

    @discardableResult
    func renameChat(_ id: UUID, title: String) -> Bool {
        guard chatActions(for: id)?.canRename == true else { return false }
        return renameConversation(id, title: title)
    }

    @discardableResult
    func toggleChatPin(_ id: UUID) -> Bool {
        guard chatActions(for: id)?.canPin == true else { return false }
        let wasPinned = sidebarState.sidebarOrganization.isPinned(.conversation(id))
        toggleSidebarPin(.conversation(id))
        return sidebarState.sidebarOrganization.isPinned(.conversation(id)) != wasPinned
    }

    @discardableResult
    func archiveChat(_ id: UUID) -> Bool {
        guard chatActions(for: id)?.canArchive == true else { return false }
        guard changeSidebar({ organization in
            organization.registerConversation(id: id)
            try organization.archiveConversations(ids: [id])
        }) else { return false }
        if selectedConversationID == id { newConversation() }
        return true
    }

    func chatExport(for id: UUID) -> VyronChatExport? {
        guard chatActions(for: id)?.canExport == true,
            let conversation = conversations.first(where: { $0.id == id }) else { return nil }
        return VyronChatExport(conversation: conversation)
    }

    func canNavigateFromChat(_ id: UUID) -> Bool {
        canTransitionForegroundConversation
            && !isSideChatGenerating(id) && !isSidebarConversationActive(id)
            && !composer.isEditingQueuedMessage && composer.pendingSteeringIDs.isEmpty
            && (conversations.first { $0.id == id }?.queuedMessages ?? []).isEmpty
            && (selectedConversation?.queuedMessages ?? []).isEmpty
            && composer.trimmedDraft.isEmpty && composerAttachments.attachedFiles.isEmpty
            && !composerAttachments.hasDrafts && !composerAttachments.isImporting && !workspaceState.isLoadingWorkspace
    }

    private func canArchiveUnselectedChat(_ id: UUID) -> Bool {
        !isSidebarConversationActive(id)
            && (conversations.first { $0.id == id }?.queuedMessages ?? []).isEmpty
    }
}
