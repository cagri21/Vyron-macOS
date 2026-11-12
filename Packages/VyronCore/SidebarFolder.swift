import Foundation

public struct SidebarFolder: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public private(set) var name: String
    public private(set) var parentID: UUID?

    init(id: UUID = UUID(), name: String, parentID: UUID?) {
        self.id = id
        self.name = name
        self.parentID = parentID
    }

    mutating func rename(_ name: String) { self.name = name }
    mutating func reparent(_ id: UUID?) { parentID = id }
}
