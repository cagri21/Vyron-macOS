import Foundation

enum VyronMacWorkProject {
    static func resolve(path: String, root: URL?) throws -> URL {
        guard let root, root.isFileURL, !path.isEmpty, path.utf8.count <= 4_096,
            !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\0"),
            !path.contains("\\"), !path.contains("\n"), !path.contains("\r")
        else { throw failure() }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw failure() }
        var candidate = root.standardizedFileURL
        try requireDirectory(candidate)
        for component in components {
            candidate.appendPathComponent(String(component), isDirectory: true)
            try requireDirectory(candidate)
        }
        guard ["xcodeproj", "xcworkspace"].contains(candidate.pathExtension.lowercased()),
            candidate.path.hasPrefix(root.standardizedFileURL.path + "/"),
            candidate.resolvingSymlinksInPath().path == candidate.path
        else { throw failure() }
        return candidate
    }

    private static func requireDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw failure() }
    }

    private static func failure() -> VyronMacWorkError {
        VyronMacWorkError(message: "Use an existing relative .xcodeproj or .xcworkspace directory inside the active "
            + "project. Parent traversal and symbolic links are unavailable.")
    }
}
