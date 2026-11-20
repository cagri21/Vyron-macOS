import VyronCore

enum VyronSidebarSection: String, CaseIterable {
    case pinned
    case folders
    case projects
    case chats

    var group: VyronSidebarGroup {
        switch self {
        case .pinned: .pinned
        case .folders: .rootFolders
        case .projects: .rootProjects
        case .chats: .rootChats
        }
    }

    var title: String {
        switch self {
        case .pinned: VyronSidebarText.pinned
        case .folders: VyronSidebarText.folders
        case .projects: VyronSidebarText.projects
        case .chats: VyronSidebarText.chats
        }
    }
}
