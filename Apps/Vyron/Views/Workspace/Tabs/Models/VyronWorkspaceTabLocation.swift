enum VyronWorkspaceTabLocation: Equatable, Sendable {
    case conversation
    case home
    case website(VyronWorkspaceWebsiteLocation)
    case page(VyronWorkspacePageLocation)

    var kind: VyronWorkspaceTabKind {
        switch self {
        case .conversation: .conversation
        case .home: .home
        case .website: .website
        case .page: .page
        }
    }
}
