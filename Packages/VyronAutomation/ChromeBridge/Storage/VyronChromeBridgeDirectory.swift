import Darwin
import Foundation

/// Descriptor-relative storage prevents symlink traversal, including when a parent path is replaced.
final class VyronChromeBridgeDirectory {
    let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }

    deinit { Darwin.close(descriptor) }

    static func open(
        _ url: URL,
        create: Bool,
        privateDirectory: Bool = true
    ) throws -> VyronChromeBridgeDirectory {
        guard url.isFileURL, url.path.hasPrefix("/"), url.standardizedFileURL.path == url.path else {
            throw VyronChromeBridgeError.invalidPath
        }
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw VyronChromeBridgeError.storage }
        do {
            let parts = url.pathComponents.dropFirst()
            for (index, part) in parts.enumerated() {
                if create, mkdirat(descriptor, part, 0o700) != 0, errno != EEXIST {
                    throw VyronChromeBridgeError.storage
                }
                let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw VyronChromeBridgeError.invalidPath }
                Darwin.close(descriptor)
                descriptor = next
                if index == parts.count - 1 {
                    if privateDirectory { try validate(descriptor, directory: true) }
                    else {
                        var info = stat()
                        guard fstat(descriptor, &info) == 0,
                            [geteuid(), 0].contains(info.st_uid), info.st_mode & 0o022 == 0
                        else { throw VyronChromeBridgeError.invalidPath }
                    }
                }
            }
            return VyronChromeBridgeDirectory(descriptor: descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    func child(_ name: String, create: Bool) throws -> VyronChromeBridgeDirectory {
        try Self.validateName(name)
        if create, mkdirat(descriptor, name, 0o700) != 0, errno != EEXIST {
            throw VyronChromeBridgeError.storage
        }
        let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { throw VyronChromeBridgeError.invalidPath }
        do { try Self.validate(child, directory: true) }
        catch { Darwin.close(child); throw error }
        return VyronChromeBridgeDirectory(descriptor: child)
    }

    func names() throws -> [String] {
        let copied = dup(descriptor)
        guard copied >= 0 else { throw VyronChromeBridgeError.storage }
        guard let directory = fdopendir(copied) else {
            Darwin.close(copied)
            throw VyronChromeBridgeError.storage
        }
        defer { closedir(directory) }
        rewinddir(directory)
        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name != ".", name != "..", !name.hasSuffix(".tmp") { names.append(name) }
            guard names.count <= 256 else { throw VyronChromeBridgeError.storage }
            errno = 0
        }
        guard errno == 0 else { throw VyronChromeBridgeError.storage }
        return names
    }

    func read(_ name: String) throws -> Data? {
        try Self.validateName(name)
        let file = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if file < 0, errno == ENOENT { return nil }
        guard file >= 0 else { throw VyronChromeBridgeError.invalidPath }
        defer { Darwin.close(file) }
        try Self.validate(file, directory: false)
        var info = stat()
        guard fstat(file, &info) == 0, info.st_size > 0,
            info.st_size <= VyronChromeBridgePolicy.messageLimit
        else { throw VyronChromeBridgeError.invalidMessage }
        var data = Data(count: Int(info.st_size))
        let count = data.withUnsafeMutableBytes { bytes in Darwin.read(file, bytes.baseAddress, bytes.count) }
        guard count == data.count else { throw VyronChromeBridgeError.storage }
        return data
    }

    func write(_ name: String, data: Data, replacing: Bool = false) throws {
        try Self.validateName(name)
        guard !data.isEmpty, data.count <= VyronChromeBridgePolicy.messageLimit else {
            throw VyronChromeBridgeError.invalidMessage
        }
        let temporary = UUID().uuidString + ".tmp"
        let file = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw VyronChromeBridgeError.storage }
        defer { Darwin.close(file); unlinkat(descriptor, temporary, 0) }
        try Self.validate(file, directory: false)
        var offset = 0
        try data.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { throw VyronChromeBridgeError.invalidMessage }
            while offset < bytes.count {
                let count = Darwin.write(file, address.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw VyronChromeBridgeError.storage }
                offset += count
            }
        }
        guard fsync(file) == 0 else { throw VyronChromeBridgeError.storage }
        if replacing {
            var info = stat()
            if fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 {
                guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
                    info.st_nlink == 1, info.st_mode & 0o077 == 0
                else { throw VyronChromeBridgeError.invalidPath }
            } else if errno != ENOENT { throw VyronChromeBridgeError.storage }
        }
        let flags: UInt32 = replacing ? 0 : UInt32(RENAME_EXCL)
        guard renameatx_np(descriptor, temporary, descriptor, name, flags) == 0 else {
            throw VyronChromeBridgeError.storage
        }
    }

    func remove(_ name: String, directory: Bool = false) throws {
        try Self.validateName(name)
        guard unlinkat(descriptor, name, directory ? AT_REMOVEDIR : 0) == 0 || errno == ENOENT else {
            throw VyronChromeBridgeError.storage
        }
    }

    func validateExecutable(_ name: String) throws {
        try Self.validateName(name)
        let file = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard file >= 0 else { throw VyronChromeBridgeError.invalidPath }
        defer { Darwin.close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            [geteuid(), 0].contains(info.st_uid), info.st_mode & 0o022 == 0,
            info.st_mode & 0o111 != 0
        else { throw VyronChromeBridgeError.invalidPath }
    }

    static func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0"),
            name.utf8.count <= 128
        else { throw VyronChromeBridgeError.invalidPath }
    }

    private static func validate(_ descriptor: Int32, directory: Bool) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
            info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG),
            info.st_uid == geteuid(), info.st_mode & 0o077 == 0,
            directory || info.st_nlink == 1
        else { throw VyronChromeBridgeError.invalidPath }
    }
}
