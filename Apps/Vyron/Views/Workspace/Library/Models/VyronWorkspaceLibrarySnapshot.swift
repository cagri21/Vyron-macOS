struct VyronWorkspaceLibrarySnapshot: Codable, Equatable, Sendable {
    var version = 1
    var pages: [VyronWorkspacePage] = []
    var links: [VyronWorkspaceLink] = []
    var recents: [VyronWorkspaceRecentItem] = []
}
