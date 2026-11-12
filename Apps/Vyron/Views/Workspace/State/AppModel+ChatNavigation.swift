import Foundation

extension AppModel {
    func chatDeepLink(for id: UUID) -> URL? {
        guard chatActions(for: id)?.canExport == true else { return nil }
        return VyronChatDeepLink(conversationID: id).url
    }

    func chatWorkingDirectory(for id: UUID) -> String? {
        guard chatActions(for: id)?.canExport == true,
            let path = conversations.first(where: { $0.id == id })?.workspacePath,
            path.hasPrefix("/"),
            !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return path
    }

    @discardableResult
    func openChatDeepLink(_ url: URL) -> Bool {
        guard !isShuttingDown, let link = VyronChatDeepLink(url: url),
            conversations.contains(where: { $0.id == link.conversationID }),
            !sidebarState.sidebarOrganization.isConversationArchived(link.conversationID) else {
            errorMessage = VyronHeaderText.deepLinkUnavailable
            return false
        }
        let sourceID = selectedConversationID ?? link.conversationID
        guard selectedConversationID == link.conversationID || canNavigateFromChat(sourceID) else {
            errorMessage = VyronHeaderText.deepLinkBusy
            return false
        }
        guard markChatRead(link.conversationID) else { return false }
        selectConversation(link.conversationID)
        return selectedConversationID == link.conversationID
    }
}
