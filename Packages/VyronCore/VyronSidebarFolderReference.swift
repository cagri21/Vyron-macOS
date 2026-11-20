import Foundation

public struct VyronSidebarFolderReference: Hashable, Codable, Sendable {
    public let id: UUID

    public init(id: UUID) { self.id = id }
}
