public enum VyronSidebarRow: Hashable, Codable, Sendable {
    case folder(VyronSidebarFolderReference)
    case item(SidebarItem)
}
