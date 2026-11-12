import Foundation

struct VyronWorkspaceRecentItem: Codable, Equatable, Identifiable, Sendable {
    var reference: VyronWorkspaceRecentReference
    var openedAt: Date

    var id: String { reference.id }
    var kind: VyronWorkspaceRecentKind { reference.kind }
    var title: String { reference.title }
    var url: URL { reference.url }
}
