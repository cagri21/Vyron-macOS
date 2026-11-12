import Darwin
import Foundation

/// Creates missing project guidance without replacing any existing filesystem entry.
public enum VyronProjectSetup {
    public static func prepare(at rootURL: URL) throws -> VyronProjectSetupResult {
        let root = try canonicalRoot(rootURL)
        let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            let errorCode = errno
            throw filesystemError(errorCode, at: root.path)
        }
        defer { close(descriptor) }

        let context = try VyronProjectSetupContext.inspect(root: root, descriptor: descriptor)
        let files = VyronProjectSetupTemplates.files(context: context)
        var created: [String] = []
        var preserved: [String] = []
        for file in files {
            if try create(file, relativeTo: descriptor, root: root) {
                created.append(file.path)
            } else {
                preserved.append(file.path)
            }
        }
        return VyronProjectSetupResult(createdPaths: created, preservedPaths: preserved)
    }

    private static func canonicalRoot(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .canonicalPathKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadInvalidFileName, userInfo: [NSFilePathErrorKey: url.path])
        }
        let root = URL(
            fileURLWithPath: values.canonicalPath ?? url.resolvingSymlinksInPath().path,
            isDirectory: true
        )
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let forbidden = ["/", "/Users", "/System", "/Library", "/Applications", "/private", "/private/tmp"]
        guard root.path != home.path, !forbidden.contains(root.path) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: root.path])
        }
        return root
    }

    private static func create(
        _ file: VyronProjectSetupFile,
        relativeTo rootDescriptor: Int32,
        root: URL
    ) throws -> Bool {
        let descriptor = openat(rootDescriptor, file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            let errorCode = errno
            // O_EXCL treats files, directories and even dangling symbolic links as existing entries.
            if errorCode == EEXIST { return false }
            throw filesystemError(errorCode, at: root.appendingPathComponent(file.path).path)
        }
        defer { close(descriptor) }
        let data = Data(file.contents.utf8)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(descriptor, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    let errorCode = count < 0 ? errno : EIO
                    throw filesystemError(errorCode, at: root.appendingPathComponent(file.path).path)
                }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else {
            let errorCode = errno
            throw filesystemError(errorCode, at: root.appendingPathComponent(file.path).path)
        }
        return true
    }

    private static func filesystemError(_ code: Int32, at path: String) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
    }
}
