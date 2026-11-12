import Darwin
import Foundation

struct VyronProjectSetupContext: Sendable {
    let projectName: String
    let manifests: [String]

    static func inspect(root: URL, descriptor: Int32) throws -> Self {
        let candidates = [
            "Package.swift", "package.json", "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod",
            "Gemfile", "Makefile"
        ]
        var manifests: [String] = []
        for path in candidates {
            var information = stat()
            if fstatat(descriptor, path, &information, AT_SYMLINK_NOFOLLOW) == 0 {
                if information.st_mode & S_IFMT == S_IFREG { manifests.append(path) }
            } else if errno != ENOENT {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(errno),
                    userInfo: [NSFilePathErrorKey: root.appendingPathComponent(path).path]
                )
            }
        }
        let name = root.lastPathComponent.components(separatedBy: .controlCharacters).joined(separator: " ")
        return Self(projectName: name, manifests: manifests)
    }
}
