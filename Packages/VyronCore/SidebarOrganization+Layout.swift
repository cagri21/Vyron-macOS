import Foundation

extension SidebarOrganization {
    /// Applies the saved relative order while keeping unlisted rows in their default slots.
    public func orderedRows(in group: VyronSidebarGroup, defaultOrder: [VyronSidebarRow]) -> [VyronSidebarRow] {
        guard let saved = layout?.orders.first(where: { $0.group == group })?.rows else { return defaultOrder }
        let available = Set(defaultOrder)
        let ordered = saved.filter { available.contains($0) }
        let savedRows = Set(ordered)
        var iterator = ordered.makeIterator()
        return defaultOrder.map { row in savedRows.contains(row) ? iterator.next() ?? row : row }
    }

    public mutating func setRowOrder(_ rows: [VyronSidebarRow], in group: VyronSidebarGroup) {
        guard isRegistered(group), rows.count == Set(rows).count else { return }
        let registeredRows = registeredSidebarRows
        guard rows.allSatisfy({ registeredRows.contains($0) && allows($0, in: group) }) else { return }
        updateSidebarLayout { $0.setRowOrder(rows, in: group) }
    }

    public mutating func removeRowOrder(_ row: VyronSidebarRow, from group: VyronSidebarGroup) {
        updateSidebarLayout { $0.removeRowOrder(row, from: group) }
    }

    /// This placement controls the sidebar only. The conversation retains its working project and folder.
    public func chatDisplayGroup(_ id: UUID) -> VyronSidebarGroup? {
        layout?.chatPlacements.first { $0.id == id }?.group
    }

    public mutating func setChatDisplayGroup(_ group: VyronSidebarGroup?, for id: UUID) {
        guard conversationIDs.contains(id) else { return }
        if let group, !isChatDisplayGroup(group) { return }
        updateSidebarLayout { $0.setChatDisplayGroup(group, for: id) }
    }

    mutating func updateSidebarLayout(_ change: (inout VyronSidebarLayout) -> Void) {
        var updated = layout ?? VyronSidebarLayout()
        change(&updated)
        layout = updated.isEmpty ? nil : updated
    }

    func validateSidebarLayout() throws {
        guard let layout else { return }
        let registeredRows = registeredSidebarRows
        guard Set(layout.orders.map(\.group)).count == layout.orders.count,
            layout.orders.allSatisfy({ order in
                isRegistered(order.group) && !order.rows.isEmpty && Set(order.rows).count == order.rows.count
                    && order.rows.allSatisfy { registeredRows.contains($0) && allows($0, in: order.group) }
            })
        else { throw SidebarOrganizationError.invalidOrganization("A saved sidebar row order is invalid.") }
        guard Set(layout.chatPlacements.map(\.id)).count == layout.chatPlacements.count,
            layout.chatPlacements.allSatisfy({ placement in
                registeredRows.contains(.item(.conversation(placement.id))) && isChatDisplayGroup(placement.group)
            })
        else { throw SidebarOrganizationError.invalidOrganization("A saved chat display placement is invalid.") }
    }

    private var registeredSidebarRows: Set<VyronSidebarRow> {
        let folderRows = folders.map { VyronSidebarRow.folder(VyronSidebarFolderReference(id: $0.id)) }
        let projectRows = allProjects.map { VyronSidebarRow.item(.project($0)) }
        let chatRows = conversationIDs.map { VyronSidebarRow.item(.conversation($0)) }
        return Set(folderRows + projectRows + chatRows)
    }

    private func isRegistered(_ group: VyronSidebarGroup) -> Bool {
        switch group {
        case .folder(let folder): folders.contains { $0.id == folder.id }
        case .project(let project): allProjects.contains(project.path)
        case .pinned, .rootFolders, .rootProjects, .rootChats: true
        }
    }

    private func isChatDisplayGroup(_ group: VyronSidebarGroup) -> Bool {
        switch group {
        case .rootChats, .project: isRegistered(group)
        default: false
        }
    }

    private func allows(_ row: VyronSidebarRow, in group: VyronSidebarGroup) -> Bool {
        switch (group, row) {
        case (.pinned, .item), (.rootFolders, .folder), (.rootProjects, .item(.project)),
            (.rootChats, .item(.conversation)), (.project, .item(.conversation)):
            true
        case (.folder(let folder), _): row != .folder(folder)
        default: false
        }
    }
}
