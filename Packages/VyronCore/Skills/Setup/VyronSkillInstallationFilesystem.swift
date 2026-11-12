import Darwin
import Foundation

/// All package reads and installation writes stay relative to descriptors opened without following links.
enum VyronSkillInstallationFilesystem {
    static func openDirectory(_ directory: URL, create: Bool = false) throws -> Int32 {
        guard directory.isFileURL, directory.path.hasPrefix("/"),
            !directory.path.contains("\0"),
            directory.pathComponents.dropFirst().allSatisfy({ $0 != "." && $0 != ".." })
        else { throw VyronSkillInstallError.unsafePath }
        let root = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard root >= 0 else { throw fileError() }
        defer { Darwin.close(root) }
        return try openRelativeDirectory(directory.pathComponents.dropFirst().joined(separator: "/"), in: root, create: create)
    }

    static func openRelativeDirectory(_ path: String, in parent: Int32, create: Bool = false) throws -> Int32 {
        var descriptor = dup(parent)
        guard descriptor >= 0 else { throw fileError() }
        do {
            for component in path.split(separator: "/").map(String.init) {
                try validate(component)
                if create {
                    var information = stat()
                    if fstatat(descriptor, component, &information, AT_SYMLINK_NOFOLLOW) != 0 {
                        guard errno == ENOENT else { throw fileError() }
                        guard mkdirat(descriptor, component, 0o700) == 0 || errno == EEXIST else { throw fileError() }
                    }
                }
                let child = try openChildDirectory(component, in: descriptor)
                Darwin.close(descriptor)
                descriptor = child
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func openChildDirectory(_ name: String, in parent: Int32) throws -> Int32 {
        try validate(name)
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ELOOP || errno == ENOTDIR { throw VyronSkillInstallError.unsafePath }
            throw fileError()
        }
        return descriptor
    }

    static func entries(in descriptor: Int32) throws -> [String] {
        let copy = dup(descriptor)
        guard copy >= 0 else { throw fileError() }
        guard let directory = fdopendir(copy) else {
            Darwin.close(copy)
            throw fileError()
        }
        defer { closedir(directory) }
        // dup() shares the directory offset; rewind so the held descriptor remains reusable.
        rewinddir(directory)
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw fileError() }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(validatingCString: $0)
                }
            }
            guard let name else { throw VyronSkillInstallError.unsafePath }
            if name == "." || name == ".." { continue }
            try validate(name)
            guard result.count < VyronSkillInstallationLimits.maximumEntries else {
                throw VyronSkillInstallError.packageTooLarge
            }
            result.append(name)
        }
        return result.sorted()
    }

    static func readFile(_ name: String, in parent: Int32, limit: Int) throws -> Data {
        let descriptor = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ELOOP { throw VyronSkillInstallError.unsafePath }
            throw fileError()
        }
        defer { Darwin.close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0 else { throw fileError() }
        guard information.st_mode & S_IFMT == S_IFREG else { throw VyronSkillInstallError.invalidPackage }
        guard information.st_size <= limit else { throw VyronSkillInstallError.packageTooLarge }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var result = Data()
        while true {
            try Task.checkCancellation()
            let bytes = try handle.read(upToCount: min(VyronSkillInstallationLimits.copyChunkBytes, limit + 1 - result.count))
                ?? Data()
            if bytes.isEmpty { return result }
            result.append(bytes)
            guard result.count <= limit else { throw VyronSkillInstallError.packageTooLarge }
        }
    }

    static func write(_ file: VyronSkillInstallationFile, in parent: Int32) throws {
        let parts = file.relativePath.split(separator: "/").map(String.init)
        guard let name = parts.last else { throw VyronSkillInstallError.unsafePath }
        let directory = try openRelativeDirectory(parts.dropLast().joined(separator: "/"), in: parent)
        defer { Darwin.close(directory) }
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw fileError() }
        defer { Darwin.close(descriptor) }
        try file.content.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                guard let address = bytes.baseAddress else { throw VyronSkillInstallError.invalidPackage }
                let count = Darwin.write(
                    descriptor,
                    address.advanced(by: offset),
                    min(VyronSkillInstallationLimits.copyChunkBytes, bytes.count - offset)
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw fileError() }
                offset += count
            }
        }
    }

    static func exists(_ name: String, in parent: Int32) throws -> Bool {
        var information = stat()
        if fstatat(parent, name, &information, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        guard errno == ENOENT else { throw fileError() }
        return false
    }

    static func removeStaging(_ name: String, in parent: Int32, descriptor: Int32) throws {
        var expected = stat()
        var actual = stat()
        guard fstat(descriptor, &expected) == 0,
            fstatat(parent, name, &actual, AT_SYMLINK_NOFOLLOW) == 0
        else { throw fileError() }
        guard actual.st_mode & S_IFMT == S_IFDIR,
            actual.st_ino == expected.st_ino, actual.st_dev == expected.st_dev
        else { throw VyronSkillInstallError.unsafePath }
        try removeContents(in: descriptor)
        guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw fileError() }
    }

    private static func removeContents(in parent: Int32) throws {
        for name in try entries(in: parent) {
            var information = stat()
            guard fstatat(parent, name, &information, AT_SYMLINK_NOFOLLOW) == 0 else { throw fileError() }
            if information.st_mode & S_IFMT == S_IFDIR {
                let child = try openChildDirectory(name, in: parent)
                defer { Darwin.close(child) }
                try removeContents(in: child)
                guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw fileError() }
            } else {
                guard unlinkat(parent, name, 0) == 0 else { throw fileError() }
            }
        }
    }

    private static func validate(_ component: String) throws {
        guard !component.isEmpty, component != ".", component != "..",
            !component.contains("/"), !component.contains("\\"), !component.contains("\0")
        else { throw VyronSkillInstallError.unsafePath }
    }

    static func fileError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
