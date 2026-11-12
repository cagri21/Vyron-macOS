import Foundation

struct VyronQueuedMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var content: String

    init(id: UUID = UUID(), content: String) {
        self.id = id
        self.content = content
    }
}
