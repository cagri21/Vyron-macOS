enum VyronSidebarHint {
    case emptyFolder
    case emptyProjects
    case noResults

    var title: String {
        switch self {
        case .emptyFolder: VyronSidebarText.emptyFolder
        case .emptyProjects: VyronSidebarText.emptyProjects
        case .noResults: VyronSidebarText.noResults
        }
    }
}
