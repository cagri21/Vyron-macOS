enum VyronSidebarSection {
    case pinned
    case folders
    case projects
    case chats

    var title: String {
        switch self {
        case .pinned: VyronSidebarText.pinned
        case .folders: VyronSidebarText.folders
        case .projects: VyronSidebarText.projects
        case .chats: VyronSidebarText.chats
        }
    }
}
