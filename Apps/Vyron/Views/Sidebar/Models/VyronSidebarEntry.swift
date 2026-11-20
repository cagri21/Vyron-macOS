import VyronCore

struct VyronSidebarEntry: Identifiable {
    let id: String
    let kind: VyronSidebarEntryKind
    let depth: Int
    let group: VyronSidebarGroup?

    init(id: String, kind: VyronSidebarEntryKind, depth: Int, group: VyronSidebarGroup? = nil) {
        self.id = id
        self.kind = kind
        self.depth = depth
        self.group = group
    }

    var row: VyronSidebarRow? {
        switch kind {
        case .folder(let folder): .folder(VyronSidebarFolderReference(id: folder.id))
        case .project(let project): .item(.project(project.path))
        case .chat(let chat): .item(.conversation(chat.conversation.id))
        case .section, .hint, .overflow: nil
        }
    }
}
