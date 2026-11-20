import Foundation

struct VyronSidebarLayout: Codable, Equatable, Sendable {
    private(set) var orders: [VyronSidebarRowOrder] = []
    private(set) var chatPlacements: [VyronSidebarChatDisplayPlacement] = []

    var isEmpty: Bool { orders.isEmpty && chatPlacements.isEmpty }

    mutating func setRowOrder(_ rows: [VyronSidebarRow], in group: VyronSidebarGroup) {
        if let index = orders.firstIndex(where: { $0.group == group }) {
            if rows.isEmpty {
                orders.remove(at: index)
            } else {
                orders[index].rows = rows
            }
        } else if !rows.isEmpty {
            orders.append(VyronSidebarRowOrder(group: group, rows: rows))
        }
    }

    mutating func setChatDisplayGroup(_ group: VyronSidebarGroup?, for id: UUID) {
        if let index = chatPlacements.firstIndex(where: { $0.id == id }) {
            if let group {
                chatPlacements[index].group = group
            } else {
                chatPlacements.remove(at: index)
            }
        } else if let group {
            chatPlacements.append(VyronSidebarChatDisplayPlacement(id: id, group: group))
        }
    }

    mutating func removeRow(_ row: VyronSidebarRow) {
        for index in orders.indices { orders[index].rows.removeAll { $0 == row } }
        orders.removeAll { $0.rows.isEmpty }
    }

    mutating func removeRowOrder(_ row: VyronSidebarRow, from group: VyronSidebarGroup) {
        guard let index = orders.firstIndex(where: { $0.group == group }) else { return }
        orders[index].rows.removeAll { $0 == row }
        if orders[index].rows.isEmpty { orders.remove(at: index) }
    }

    mutating func removeFolder(_ id: UUID) {
        let folder = VyronSidebarFolderReference(id: id)
        removeRow(.folder(folder))
        removeGroup(.folder(folder))
    }

    mutating func removeItem(_ item: SidebarItem) {
        removeRow(.item(item))
        switch item {
        case .conversation(let id): setChatDisplayGroup(nil, for: id)
        case .project(let path): removeGroup(.project(VyronSidebarProjectReference(path: path)))
        }
    }

    private mutating func removeGroup(_ group: VyronSidebarGroup) {
        orders.removeAll { $0.group == group }
        chatPlacements.removeAll { $0.group == group }
    }
}
