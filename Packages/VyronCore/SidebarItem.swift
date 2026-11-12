import Foundation

public enum SidebarItem: Hashable, Codable, Sendable, Identifiable {
    case project(String)
    case conversation(UUID)

    public var id: String {
        switch self {
        case .project(let path): "project:" + path
        case .conversation(let id): "conversation:" + id.uuidString
        }
    }
}
