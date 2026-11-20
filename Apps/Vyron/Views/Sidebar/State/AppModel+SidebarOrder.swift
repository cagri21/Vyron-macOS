import Foundation
import VyronCore

extension AppModel {
    func sidebarRows(in group: VyronSidebarGroup) -> [VyronSidebarRow] {
        let organization = sidebarState.sidebarOrganization
        let defaultOrder: [VyronSidebarRow]
        switch group {
        case .pinned:
            defaultOrder = organization.pinnedItems.map(VyronSidebarRow.item)
        case .rootFolders:
            defaultOrder = sidebarFolderRows(in: nil)
        case .rootProjects:
            defaultOrder = sidebarProjectRows(in: nil)
        case .folder(let folder):
            defaultOrder = sidebarFolderRows(in: folder.id) + sidebarProjectRows(in: folder.id)
                + sidebarConversationRows(in: group)
        case .project, .rootChats:
            defaultOrder = sidebarConversationRows(in: group)
        }
        return organization.orderedRows(in: group, defaultOrder: defaultOrder).filter { row in
            if case .item(.conversation(let id)) = row { return !organization.isConversationArchived(id) }
            return true
        }
    }

    private func sidebarGroup(for conversation: Conversation, registeredProjects: Set<String>) -> VyronSidebarGroup {
        let organization = sidebarState.sidebarOrganization
        let item = SidebarItem.conversation(conversation.id)
        if organization.isPinned(item) { return .pinned }
        if let folderID = organization.folderID(for: item) {
            return .folder(VyronSidebarFolderReference(id: folderID))
        }
        if let group = organization.chatDisplayGroup(conversation.id) { return group }
        if let path = conversation.sidebarProjectPath {
            let reference = VyronSidebarProjectReference(path: URL(fileURLWithPath: path).standardizedFileURL.path)
            if registeredProjects.contains(reference.path) { return .project(reference) }
        }
        return .rootChats
    }

    func canMoveSidebarRow(_ row: VyronSidebarRow, to destination: VyronSidebarDestination) -> Bool {
        do { return try sidebarOrganizationMoving(row, to: destination) != nil }
        catch { return false }
    }

    @discardableResult
    func moveSidebarRow(_ row: VyronSidebarRow, to destination: VyronSidebarDestination) -> Bool {
        var hasMove = false
        let saved = changeSidebar { organization in
            guard let updated = try sidebarOrganizationMoving(row, to: destination) else { return }
            organization = updated
            hasMove = true
        }
        return saved && hasMove
    }

    private func sidebarOrganizationMoving(
        _ row: VyronSidebarRow,
        to destination: VyronSidebarDestination
    ) throws -> SidebarOrganization? {
        guard !isShuttingDown, let source = sidebarGroup(for: row) else { return nil }
        let destinationRows = sidebarRows(in: destination.group)
        var siblings = destinationRows.filter { $0 != row }
        guard let index = destination.position.index(in: siblings) else { return nil }
        siblings.insert(row, at: index)
        guard source != destination.group || siblings != destinationRows else { return nil }

        var updated = sidebarState.sidebarOrganization
        if source != destination.group {
            guard try placeSidebarRow(row, in: destination.group, organization: &updated) else { return nil }
            if destination.group != .pinned { updated.removeRowOrder(row, from: source) }
        }
        updated.setRowOrder(siblings, in: destination.group)
        return updated
    }

    private func sidebarGroup(for row: VyronSidebarRow) -> VyronSidebarGroup? {
        let organization = sidebarState.sidebarOrganization
        switch row {
        case .folder(let reference):
            guard let folder = organization.folders.first(where: { $0.id == reference.id }) else { return nil }
            return folder.parentID.map { .folder(VyronSidebarFolderReference(id: $0)) } ?? .rootFolders
        case .item(.project(let path)):
            guard organization.contains(.project(path)) else { return nil }
            if organization.isPinned(.project(path)) { return .pinned }
            return organization.folderID(for: .project(path)).map { .folder(VyronSidebarFolderReference(id: $0)) }
                ?? .rootProjects
        case .item(.conversation(let id)):
            guard organization.contains(.conversation(id)), let conversation = sidebarConversation(id) else {
                return nil
            }
            return sidebarGroup(for: conversation, registeredProjects: Set(organization.allProjects))
        }
    }

    private func placeSidebarRow(
        _ row: VyronSidebarRow,
        in group: VyronSidebarGroup,
        organization: inout SidebarOrganization
    ) throws -> Bool {
        switch (row, group) {
        case (.folder(let folder), .rootFolders):
            try organization.moveFolder(id: folder.id, toParent: nil)
        case (.folder(let folder), .folder(let parent)):
            try organization.moveFolder(id: folder.id, toParent: parent.id)
        case (.item(let item), .folder(let folder)):
            try Self.placeSidebarItem(item, in: folder.id, organization: &organization)
        case (.item(.project(let path)), .rootProjects):
            try Self.placeSidebarItem(.project(path), in: nil, organization: &organization)
        case (.item(.conversation(let id)), .rootChats):
            try Self.placeSidebarItem(.conversation(id), in: nil, organization: &organization)
            organization.setChatDisplayGroup(group, for: id)
        case (.item(.conversation(let id)), .project(let project)):
            guard organization.contains(.project(project.path)) else { return false }
            try Self.placeSidebarItem(.conversation(id), in: nil, organization: &organization)
            organization.setChatDisplayGroup(group, for: id)
            try Self.expandSidebarProject(project.path, in: &organization)
        case (.item(let item), .pinned):
            if !organization.isPinned(item) { try organization.togglePin(item) }
        default:
            return false
        }

        if case .folder(let folder) = group {
            try Self.expandSidebarAncestors(folder.id, in: &organization)
        }
        return true
    }

    private static func placeSidebarItem(
        _ item: SidebarItem,
        in folderID: UUID?,
        organization: inout SidebarOrganization
    ) throws {
        if organization.isPinned(item) { try organization.togglePin(item) }
        if organization.folderID(for: item) != folderID { try organization.move(item, to: folderID) }
        if case .conversation(let id) = item { organization.setChatDisplayGroup(nil, for: id) }
    }

    private func sidebarFolderRows(in folderID: UUID?) -> [VyronSidebarRow] {
        sidebarState.sidebarOrganization.folderChildren(of: folderID).map {
            .folder(VyronSidebarFolderReference(id: $0.id))
        }
    }

    private func sidebarProjectRows(in folderID: UUID?) -> [VyronSidebarRow] {
        let organization = sidebarState.sidebarOrganization
        return organization.allProjects.compactMap { path in
            let item = SidebarItem.project(path)
            guard !organization.isPinned(item), organization.folderID(for: item) == folderID else { return nil }
            return .item(item)
        }
    }

    private func sidebarConversationRows(in group: VyronSidebarGroup) -> [VyronSidebarRow] {
        let projects = Set(sidebarState.sidebarOrganization.allProjects)
        return conversations.compactMap {
            sidebarGroup(for: $0, registeredProjects: projects) == group ? .item(.conversation($0.id)) : nil
        }
    }
}
