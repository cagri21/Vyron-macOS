import Foundation

struct VyronWorkspaceRecentReference: Codable, Equatable, Sendable {
    let kind: VyronWorkspaceRecentKind
    let id: String
    var title: String
    let url: URL
}
