import Foundation

package struct VyronApplicationAttachment: Identifiable, Codable, Sendable, Equatable {
    package let id: UUID
    package let name: String
    package let path: String

    package init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    package var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}
