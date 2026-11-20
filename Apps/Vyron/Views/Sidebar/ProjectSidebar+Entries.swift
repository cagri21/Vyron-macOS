import Foundation
import VyronCore

extension ProjectSidebar {
    var entries: [VyronSidebarEntry] {
        var rows: [VyronSidebarEntry] = []
        let organization = model.sidebarState.sidebarOrganization
        let foldersByID = Dictionary(uniqueKeysWithValues: organization.folders.map { ($0.id, $0) })
        let chatsByID = Dictionary(model.conversations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func appendChat(_ conversation: Conversation, in group: VyronSidebarGroup, depth: Int) {
            let showsProject: Bool
            if case .project(let project) = group {
                showsProject = conversation.sidebarProjectPath.map {
                    URL(fileURLWithPath: $0).standardizedFileURL.path != project.path
                } ?? false
            } else {
                showsProject = true
            }
            rows.append(
                VyronSidebarEntry(
                    id: "chat:\(conversation.id)",
                    kind: .chat(
                        VyronSidebarChat(
                            conversation: conversation,
                            isPinned: group == .pinned,
                            showsProject: showsProject
                        )
                    ),
                    depth: depth,
                    group: group
                )
            )
        }

        func appendProject(_ path: String, in group: VyronSidebarGroup, depth: Int, inheritedMatch: Bool) {
            let directMatch = inheritedMatch || matches(projectName(path)) || matches(path)
            let expanded = isSearching || organization.isProjectExpanded(path)
            let chatGroup = VyronSidebarGroup.project(VyronSidebarProjectReference(path: path))
            let chatRows = expanded ? model.sidebarRows(in: chatGroup) : []
            let chats = chatRows.compactMap { row -> Conversation? in
                guard case .item(.conversation(let id)) = row else { return nil }
                return chatsByID[id]
            }
            guard !isSearching || directMatch || chats.contains(where: conversationMatches) else { return }
            rows.append(
                VyronSidebarEntry(
                    id: "project:\(path)",
                    kind: .project(VyronSidebarProject(path: path, isPinned: group == .pinned)),
                    depth: depth,
                    group: group
                )
            )
            guard expanded else { return }

            let matchingChats = chats.filter { !isSearching || directMatch || conversationMatches($0) }
            let showsAll = isSearching || expandedChatProjects.contains(path)
            let visibleChats = VyronSidebarChatPreview.visibleChats(
                matchingChats,
                selectedID: model.selectedConversationID,
                showsAll: showsAll
            )
            for conversation in visibleChats {
                appendChat(conversation, in: chatGroup, depth: depth + 1)
            }
            if !isSearching, chats.count > VyronSidebarChatPreview.limit {
                rows.append(
                    VyronSidebarEntry(
                        id: "overflow:\(path)",
                        kind: .overflow(VyronSidebarOverflow(projectPath: path, showsAll: showsAll)),
                        depth: depth + 1,
                        group: chatGroup
                    )
                )
            }
        }

        func appendFolder(_ folder: SidebarFolder, in group: VyronSidebarGroup, depth: Int, inheritedMatch: Bool) {
            rows.append(
                VyronSidebarEntry(id: "folder:\(folder.id)", kind: .folder(folder), depth: depth, group: group)
            )
            guard isSearching || organization.isFolderExpanded(folder.id) else { return }

            let firstChild = rows.count
            let folderGroup = VyronSidebarGroup.folder(VyronSidebarFolderReference(id: folder.id))
            let matchAll = inheritedMatch || matches(folder.name) || matches(folderBreadcrumb(folder.id))
            appendGroup(folderGroup, depth: depth + 1, inheritedMatch: matchAll)
            guard rows.count == firstChild else { return }
            if isSearching {
                if !matchAll { rows.removeLast() }
            } else {
                rows.append(
                    VyronSidebarEntry(
                        id: "empty:\(folder.id)",
                        kind: .hint(.emptyFolder),
                        depth: depth + 1,
                        group: folderGroup
                    )
                )
            }
        }

        func appendGroup(_ group: VyronSidebarGroup, depth: Int, inheritedMatch: Bool) {
            for row in model.sidebarRows(in: group) {
                switch row {
                case .folder(let reference):
                    if let folder = foldersByID[reference.id] {
                        appendFolder(folder, in: group, depth: depth, inheritedMatch: inheritedMatch)
                    }
                case .item(let item):
                    let locationMatch = group == .pinned && organization.folderID(for: item)
                        .map { matches(folderBreadcrumb($0)) } == true
                    let matchesParent = inheritedMatch || locationMatch
                    switch item {
                    case .project(let path):
                        appendProject(path, in: group, depth: depth, inheritedMatch: matchesParent)
                    case .conversation(let id):
                        if let chat = chatsByID[id], !isSearching || matchesParent || conversationMatches(chat) {
                            appendChat(chat, in: group, depth: depth)
                        }
                    }
                }
            }
        }

        for section in VyronSidebarSection.allCases {
            let start = rows.count
            appendGroup(section.group, depth: 0, inheritedMatch: false)
            if rows.count > start {
                rows.insert(
                    VyronSidebarEntry(
                        id: "section:\(section.rawValue)",
                        kind: .section(section),
                        depth: 0,
                        group: section.group
                    ),
                    at: start
                )
            } else if section == .projects && !isSearching && organization.allProjects.isEmpty {
                rows.append(
                    VyronSidebarEntry(
                        id: "hint:projects",
                        kind: .hint(.emptyProjects),
                        depth: 0,
                        group: .rootProjects
                    )
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
