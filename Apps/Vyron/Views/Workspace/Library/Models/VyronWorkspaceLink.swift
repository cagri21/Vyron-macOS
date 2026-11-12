import Foundation

struct VyronWorkspaceLink: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    let url: URL

    init(id: UUID = UUID(), title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}
