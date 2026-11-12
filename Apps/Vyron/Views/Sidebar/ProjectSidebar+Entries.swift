import Foundation
import VyronCore

extension ProjectSidebar {
    var entries: [VyronSidebarEntry] {
        var rows: [VyronSidebarEntry] = []
        let organization = model.sidebarState.sidebarOrganization

        func appendProject(_ path: String, depth: Int, pinned: Bool, inheritedMatch: Bool = false) {
            let directMatch = inheritedMatch || matches(projectName(path)) || matches(path)
            let chats = model.sidebarProjectChats(path)
            guard !isSearching || directMatch || chats.contains(where: conversationMatches) else { return }
            rows.append(
                VyronSidebarEntry(
                    id: "project:\(path)",
                    kind: .project(VyronSidebarProject(path: path, isPinned: pinned)),
                    depth: depth
                )
            )
            guard isSearching || organization.isProjectExpanded(path) else { return }

            let matchingChats = chats.filter { !isSearching || directMatch || conversationMatches($0) }
            let showsAll = isSearching || expandedChatProjects.contains(path)
            let visibleChats = VyronSidebarChatPreview.visibleChats(
                matchingChats,
                selectedID: model.selectedConversationID,
                showsAll: showsAll
            )
            for conversation in visibleChats {
                rows.append(
                    VyronSidebarEntry(
                        id: "chat:\(conversation.id)",
                        kind: .chat(
                            VyronSidebarChat(conversation: conversation, isPinned: false, showsProject: false)
                        ),
                        depth: depth + 1
                    )
                )
            }
            if !isSearching, chats.count > VyronSidebarChatPreview.limit {
                rows.append(
                    VyronSidebarEntry(
                        id: "overflow:\(path)",
                        kind: .overflow(VyronSidebarOverflow(projectPath: path, showsAll: showsAll)),
                        depth: depth + 1
                    )
                )
            }
        }

        func appendFolder(
            _ folder: SidebarFolder,
            depth: Int,
            inheritedMatch: Bool = false,
            visited: Set<UUID> = []
        ) {
            guard !visited.contains(folder.id),
                !isSearching || inheritedMatch || folderHasMatch(folder, visited: visited)
            else { return }
            rows.append(VyronSidebarEntry(id: "folder:\(folder.id)", kind: .folder(folder), depth: depth))
            guard isSearching || organization.isFolderExpanded(folder.id) else { return }

            let firstChild = rows.count
            let matchAll = inheritedMatch || matches(folder.name) || matches(folderBreadcrumb(folder.id))
            let nextVisited = visited.union([folder.id])
            for child in organization.folderChildren(of: folder.id) {
                appendFolder(child, depth: depth + 1, inheritedMatch: matchAll, visited: nextVisited)
            }
            for path in model.sidebarProjects(in: folder.id) {
                appendProject(path, depth: depth + 1, pinned: false, inheritedMatch: matchAll)
            }
            for conversation in model.sidebarChats(in: folder.id)
            where !isSearching || matchAll || conversationMatches(conversation) {
                rows.append(
                    VyronSidebarEntry(
                        id: "chat:\(conversation.id)",
                        kind: .chat(
                            VyronSidebarChat(conversation: conversation, isPinned: false, showsProject: true)
                        ),
                        depth: depth + 1
                    )
                )
            }
            if rows.count == firstChild && !isSearching {
                rows.append(
                    VyronSidebarEntry(id: "empty:\(folder.id)", kind: .hint(.emptyFolder), depth: depth + 1)
                )
            }
        }

        var pinnedRows: [VyronSidebarEntry] = []
        for item in organization.pinnedItems {
            let locationMatch = organization.folderID(for: item).map { matches(folderBreadcrumb($0)) } ?? false
            switch item {
            case .project(let path):
                let before = rows.count
                appendProject(path, depth: 0, pinned: true, inheritedMatch: locationMatch)
                pinnedRows += rows.suffix(rows.count - before)
                rows.removeLast(rows.count - before)
            case .conversation(let id):
                if let conversation = model.sidebarConversation(id),
                    !isSearching || locationMatch || conversationMatches(conversation) {
                    pinnedRows.append(
                        VyronSidebarEntry(
                            id: "chat:\(id)",
                            kind: .chat(
                                VyronSidebarChat(conversation: conversation, isPinned: true, showsProject: true)
                            ),
                            depth: 0
                        )
                    )
                }
            }
        }
        if !pinnedRows.isEmpty {
            rows.append(VyronSidebarEntry(id: "section:pinned", kind: .section(.pinned), depth: 0))
            rows += pinnedRows
        }

        let folderStart = rows.count
        for folder in organization.folderChildren(of: nil) {
            appendFolder(folder, depth: 0)
        }
        if rows.count > folderStart {
            rows.insert(
                VyronSidebarEntry(id: "section:folders", kind: .section(.folders), depth: 0),
                at: folderStart
            )
        }

        let projectStart = rows.count
        for path in model.sidebarProjects(in: nil) {
            appendProject(path, depth: 0, pinned: false)
        }
        if rows.count > projectStart {
            rows.insert(
                VyronSidebarEntry(id: "section:projects", kind: .section(.projects), depth: 0),
                at: projectStart
            )
        } else if !isSearching && organization.allProjects.isEmpty {
            rows.append(VyronSidebarEntry(id: "hint:projects", kind: .hint(.emptyProjects), depth: 0))
        }

        let chats = model.sidebarChats(in: nil).filter { !isSearching || conversationMatches($0) }
        if !chats.isEmpty {
            rows.append(VyronSidebarEntry(id: "section:chats", kind: .section(.chats), depth: 0))
            rows += chats.map {
                VyronSidebarEntry(
                    id: "chat:\($0.id)",
                    kind: .chat(VyronSidebarChat(conversation: $0, isPinned: false, showsProject: true)),
                    depth: 0
                )
            }
        }
        if rows.isEmpty {
            rows.append(VyronSidebarEntry(id: "hint:search", kind: .hint(.noResults), depth: 0))
        }
        return rows
    }

    func matches(_ text: String) -> Bool {
        isSearching && text.localizedCaseInsensitiveContains(query)
    }

    func conversationMatches(_ conversation: Conversation) -> Bool {
        matches(conversation.title)
            || conversation.sidebarProjectPath.map { matches($0) || matches(projectName($0)) } == true
            || conversation.workspacePath.map { matches($0) } == true
    }

    func folderHasMatch(_ folder: SidebarFolder, visited: Set<UUID> = []) -> Bool {
        guard !visited.contains(folder.id) else { return false }
        if matches(folder.name) || matches(folderBreadcrumb(folder.id)) { return true }
        if model.sidebarProjects(in: folder.id).contains(where: { path in
            matches(path) || matches(projectName(path))
                || model.sidebarProjectChats(path).contains(where: conversationMatches)
        }) {
            return true
        }
        if model.sidebarChats(in: folder.id).contains(where: conversationMatches) { return true }
        return model.sidebarState.sidebarOrganization.folderChildren(of: folder.id).contains {
            folderHasMatch($0, visited: visited.union([folder.id]))
        }
    }

    func projectName(_ path: String) -> String {
        model.sidebarProjectName(path)
    }

    func projectDisambiguation(_ path: String) -> String? {
        let peers = model.sidebarState.sidebarOrganization.allProjects.filter {
            projectName($0) == projectName(path) && $0 != path
        }
        guard !peers.isEmpty else { return nil }
        let parts = URL(fileURLWithPath: path).deletingLastPathComponent().pathComponents.filter { $0 != "/" }
        for length in 1...max(1, parts.count) {
            let suffix = parts.suffix(length).joined(separator: "/")
            if !peers.contains(where: {
                URL(fileURLWithPath: $0).deletingLastPathComponent().pathComponents.suffix(length).joined(
                    separator: "/"
                ) == suffix
            }) {
                return suffix
            }
        }
        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    func folderBreadcrumb(_ id: UUID) -> String {
        model.sidebarState.sidebarOrganization.breadcrumb(for: id).map(\.name).joined(separator: " / ")
    }

    func sortedMoveTargets(excluding id: UUID) -> [SidebarFolder] {
        model.sidebarFolderMoveTargets(excluding: id).sorted {
            folderBreadcrumb($0.id).localizedStandardCompare(folderBreadcrumb($1.id)) == .orderedAscending
        }
    }
}
