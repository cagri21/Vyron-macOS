import Darwin
import Foundation

/// Creates folders without following links or changing existing contents.
public enum VyronFolderCreation {
    private static let maximumPathBytes = 4_096
    private static let maximumComponents = 128
    private static let sensitiveNames: Set<String> = [
        ".git", ".ssh", ".gnupg", ".aws", ".azure", ".config", ".kube", ".docker",
        "credentials", "secrets", "keychains"
    ]
    private static let protectedRoots: Set<String> = [
        "/", "/Users", "/System", "/Library", "/Applications", "/private", "/private/tmp", "/private/var"
    ]

    public static func destination(for request: VyronFolderCreationRequest) throws -> URL {
        let url = try validatedDestination(for: request)
        _ = try walk(url, create: false)
        return url
    }

    public static func existingDestination(for request: VyronFolderCreationRequest) throws -> URL? {
        let url = try validatedDestination(for: request)
        guard try walk(url, create: false) != nil else { return nil }
        let values = try url.resourceValues(forKeys: [.canonicalPathKey])
        return URL(fileURLWithPath: values.canonicalPath ?? url.path, isDirectory: true)
    }

    private static func validatedDestination(for request: VyronFolderCreationRequest) throws -> URL {
        try Task.checkCancellation()
        let path = request.path
        guard !path.isEmpty, path.utf8.count <= maximumPathBytes, !path.contains("\0"),
            path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw DevelopmentError("Choose a nonempty folder path under 4,096 bytes without control characters.")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let resolvedPath: String
        if path.hasPrefix("~/") {
            let suffix = String(path.dropFirst(2))
            try validateComponents(suffix)
            resolvedPath = home.appendingPathComponent(suffix, isDirectory: true).path
        } else if path.hasPrefix("/") {
            try validateComponents(String(path.dropFirst()))
            resolvedPath = path
        } else {
            guard !path.hasPrefix("~") else {
                throw DevelopmentError("Use ~/ for your home folder, an absolute path, or a project-relative path.")
            }
            try validateComponents(path)
            guard request.projectURL.isFileURL else {
                throw DevelopmentError("The selected project must be a local folder.")
            }
            let values = try request.projectURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw DevelopmentError("The selected project must be an existing folder, not a symbolic link.")
            }
            resolvedPath = request.projectURL.resolvingSymlinksInPath()
                .appendingPathComponent(path, isDirectory: true).path
        }
        let destination = URL(fileURLWithPath: try canonicalSystemPath(resolvedPath), isDirectory: true)
        guard destination.path.utf8.count <= maximumPathBytes,
            !protectedRoots.contains(destination.path), destination.path != home.path else {
            throw DevelopmentError("Choose a specific folder rather than a home, disk, or system root.")
        }
        return destination
    }

    public static func create(_ request: VyronFolderCreationRequest) throws -> VyronFolderCreationResult {
        let url = try destination(for: request)
        let created = try walk(url, create: true) == true
        return VyronFolderCreationResult(url: url, created: created)
    }

    /// Compares an existing destination with a canonical workspace root without redirecting folder creation.
    public static func matchesProjectRoot(_ destination: URL, projectURL: URL) throws -> Bool {
        if destination.path == projectURL.path { return true }
        do {
            let values = try destination.resourceValues(forKeys: [.canonicalPathKey])
            return values.canonicalPath == projectURL.path
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            return false
        }
    }

    private static func validateComponents(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= maximumComponents,
            components.allSatisfy({ component in
                let name = component.lowercased()
                return !component.isEmpty && component != "." && component != ".."
                    && component.utf8.count <= 255 && !sensitiveNames.contains(name)
                    && !name.hasPrefix(".env") && !name.hasPrefix("credentials.")
                    && !name.hasPrefix("secrets.")
            }) else {
            throw DevelopmentError("Folder paths must exclude traversal, empty components, and sensitive folders.")
        }
    }

    private static func canonicalSystemPath(_ path: String) throws -> String {
        // macOS exposes these fixed system aliases. No user-controlled link is resolved here.
        for name in ["var", "tmp"] {
            let alias = "/" + name
            guard path == alias || path.hasPrefix(alias + "/") else { continue }
            var info = stat()
            if lstat(alias, &info) == 0, info.st_mode & S_IFMT == S_IFLNK {
                let target = try FileManager.default.destinationOfSymbolicLink(atPath: alias)
                guard target == "private/" + name || target == "/private/" + name else {
                    throw DevelopmentError("This system folder alias has an unexpected destination.")
                }
                return "/private/" + name + String(path.dropFirst(alias.count))
            }
        }
        return path
    }

    /// A missing directory returns nil during a read-only walk. Each child is opened without following links.
    private static func walk(_ url: URL, create: Bool) throws -> Bool? {
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DevelopmentError("The destination volume could not be opened safely.") }
        defer { close(descriptor) }
        let components = url.path.split(separator: "/").map(String.init)
        var created = false
        for (index, component) in components.enumerated() {
            try Task.checkCancellation()
            var next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT {
                if !create { return nil }
                try Task.checkCancellation()
                let made = mkdirat(descriptor, component, 0o755)
                guard made == 0 || errno == EEXIST else {
                    throw DevelopmentError("Could not create the requested folder: \(url.path)")
                }
                if index == components.count - 1 { created = made == 0 }
                next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard next >= 0 else {
                throw DevelopmentError("The folder path is unavailable, contains a file, or contains a symbolic link.")
            }
            close(descriptor)
            descriptor = next
        }
        return created
    }
}
