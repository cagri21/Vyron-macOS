import Foundation
import VyronCore

enum VyronSidebarSourceFolderValidator {
    static func validate(_ paths: [String]) throws -> [String] {
        guard !paths.isEmpty, paths.count <= VyronSidebarProjectSources.maximumFolderCount else {
            throw SidebarOrganizationError.invalidSourceFolders
        }
        var seen: Set<String> = []
        return try paths.map { path in
            guard path.hasPrefix("/") else { throw SidebarOrganizationError.invalidSourceFolders }
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .canonicalPathKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw SidebarOrganizationError.invalidSourceFolders
            }
            let canonical = values.canonicalPath ?? url.resolvingSymlinksInPath().path
            let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
            guard canonical != home, !unavailableRoots.contains(canonical), seen.insert(canonical).inserted else {
                throw SidebarOrganizationError.invalidSourceFolders
            }
            return canonical
        }
    }

    private static let unavailableRoots: Set<String> = [
        "/", "/Users", "/System", "/Library", "/Applications", "/private", "/private/tmp"
    ]
}
