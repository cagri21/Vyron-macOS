import Foundation

struct VyronWorkspacePage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "", body: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
    }

    var displayTitle: String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? VyronToolsText.untitledPage : value
    }
}
