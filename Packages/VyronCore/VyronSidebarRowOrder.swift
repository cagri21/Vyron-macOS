struct VyronSidebarRowOrder: Codable, Equatable, Sendable {
    let group: VyronSidebarGroup
    var rows: [VyronSidebarRow]
}
