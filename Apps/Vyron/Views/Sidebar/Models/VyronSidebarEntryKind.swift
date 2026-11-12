import VyronCore

enum VyronSidebarEntryKind {
    case section(VyronSidebarSection)
    case folder(SidebarFolder)
    case project(VyronSidebarProject)
    case chat(VyronSidebarChat)
    case hint(VyronSidebarHint)
    case overflow(VyronSidebarOverflow)
}
