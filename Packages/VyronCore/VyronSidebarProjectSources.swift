import Foundation

public struct VyronSidebarProjectSources: Codable, Sendable, Equatable {
    public static let maximumFolderCount = 16

    let path: String
    let folders: [String]

    static func normalizedFolders(_ folders: [String]) throws -> [String] {
        guard !folders.isEmpty, folders.count <= maximumFolderCount else {
            throw SidebarOrganizationError.invalidSourceFolders
        }
        let normalized = try folders.map { path in
            guard path.hasPrefix("/"), path.utf8.count <= 4_096,
                !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw SidebarOrganizationError.invalidSourceFolders }
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        guard Set(normalized).count == normalized.count else {
            throw SidebarOrganizationError.invalidSourceFolders
        }
        return normalized
    }
}
