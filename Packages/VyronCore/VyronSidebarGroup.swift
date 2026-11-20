public enum VyronSidebarGroup: Hashable, Codable, Sendable {
    case pinned
    case rootFolders
    case rootProjects
    case rootChats
    case folder(VyronSidebarFolderReference)
    case project(VyronSidebarProjectReference)
}
