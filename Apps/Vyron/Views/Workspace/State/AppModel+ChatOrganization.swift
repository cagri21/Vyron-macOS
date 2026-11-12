import Foundation
import VyronCore

extension AppModel {
    @discardableResult
    func markChatUnread(_ id: UUID) -> Bool {
        guard chatActions(for: id) != nil else { return false }
        return setChatUnread(id, unread: true)
    }

    @discardableResult
    func markChatRead(_ id: UUID) -> Bool {
        setChatUnread(id, unread: false)
    }

    @discardableResult
    func moveChatToSection(_ id: UUID, folderID: UUID?) -> Bool {
        guard chatActions(for: id) != nil else { return false }
        return moveSidebarItem(.conversation(id), toFolder: folderID)
    }

    func chatSectionName(_ folderID: UUID) -> String {
        sidebarState.sidebarOrganization.breadcrumb(for: folderID).map(\.name).joined(separator: " / ")
    }

    var chatSectionFolders: [SidebarFolder] {
        sidebarState.sidebarOrganization.folders.sorted {
            chatSectionName($0.id).localizedStandardCompare(chatSectionName($1.id)) == .orderedAscending
        }
    }

    private func setChatUnread(_ id: UUID, unread: Bool) -> Bool {
        guard !isShuttingDown, let index = conversations.firstIndex(where: { $0.id == id }) else { return false }
        let previous = conversations[index].isUnread
        guard (previous == true) != unread else { return true }
        conversations[index].isUnread = unread ? true : nil
        guard saveHistory() else {
            conversations[index].isUnread = previous
            return false
        }
        return true
    }
}
