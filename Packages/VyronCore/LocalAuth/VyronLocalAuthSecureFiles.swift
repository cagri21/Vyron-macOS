import Darwin
import Foundation

enum VyronLocalAuthSecureFiles {
    static func read(directory: URL, name: String, maximumBytes: Int) throws -> Data? {
        guard let descriptor = try directoryDescriptor(directory, create: false) else { return nil }
        defer { close(descriptor) }
        return try readFile(directory: descriptor, name: name, maximumBytes: maximumBytes)
    }

    static func updateRemovals(directory: URL, connectionID: UUID, adding: Bool) throws {
        guard let descriptor = try directoryDescriptor(directory, create: true) else {
            throw VyronLocalAuthError.invalidConfiguration
        }
        defer { close(descriptor) }
        let lock = openat(descriptor, "pending-removals.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard lock >= 0 else { throw VyronLocalAuthError.invalidConfiguration }
        defer { close(lock) }
        try validateFile(lock, maximumBytes: 0)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw VyronLocalAuthError.unavailable }
        defer { flock(lock, LOCK_UN) }
        var removals = Set(try pendingRemovals(directory: descriptor))
        if adding { removals.insert(connectionID) } else { removals.remove(connectionID) }
        guard removals.count <= 1_000 else { throw VyronLocalAuthError.invalidConfiguration }
        let data = try JSONEncoder().encode(removals.sorted { $0.uuidString < $1.uuidString })
        try writeFile(directory: descriptor, data: data)
    }

    static func pendingRemovals(directory: URL) throws -> [UUID] {
        guard let descriptor = try directoryDescriptor(directory, create: false) else { return [] }
        defer { close(descriptor) }
        return try pendingRemovals(directory: descriptor)
    }

    private static func pendingRemovals(directory: Int32) throws -> [UUID] {
        guard let data = try readFile(
            directory: directory, name: "pending-removals.json", maximumBytes: VyronLocalAuthLimits.responseBytes
        ) else { return [] }
        do {
            let values = try JSONDecoder().decode([UUID].self, from: data)
            guard values.count <= 1_000, Set(values).count == values.count else {
                throw VyronLocalAuthError.invalidConfiguration
            }
            return values
        } catch { throw VyronLocalAuthError.invalidConfiguration }
    }

    private static func directoryDescriptor(_ directory: URL, create: Bool) throws -> Int32? {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw VyronLocalAuthError.invalidConfiguration }
        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw VyronLocalAuthError.invalidConfiguration }
        for component in directory.path.split(separator: "/") {
            guard component != ".", component != ".." else {
                close(descriptor)
                throw VyronLocalAuthError.invalidConfiguration
            }
            let name = String(component)
            var next = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if next < 0, errno == ENOENT, create {
                guard mkdirat(descriptor, name, 0o700) == 0 || errno == EEXIST else {
                    close(descriptor)
                    throw VyronLocalAuthError.invalidConfiguration
                }
                next = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            }
            if next < 0 {
                let missing = errno == ENOENT
                close(descriptor)
                if missing && !create { return nil }
                throw VyronLocalAuthError.invalidConfiguration
            }
            close(descriptor)
            descriptor = next
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
            info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o777 == 0o700 else {
            close(descriptor)
            throw VyronLocalAuthError.invalidConfiguration
        }
        return descriptor
    }

    private static func readFile(directory: Int32, name: String, maximumBytes: Int) throws -> Data? {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw VyronLocalAuthError.invalidConfiguration
        }
        defer { close(descriptor) }
        try validateFile(descriptor, maximumBytes: maximumBytes)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(maximumBytes + 1, 4_096))
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else { throw VyronLocalAuthError.invalidConfiguration }
            if count == 0 { return data }
            guard data.count + count <= maximumBytes else { throw VyronLocalAuthError.invalidConfiguration }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func validateFile(_ descriptor: Int32, maximumBytes: Int) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
            info.st_mode & 0o777 == 0o600, info.st_nlink == 1, info.st_size >= 0,
            info.st_size <= maximumBytes else { throw VyronLocalAuthError.invalidConfiguration }
    }

    private static func writeFile(directory: Int32, data: Data) throws {
        let temporary = "pending-removals.\(UUID().uuidString).tmp"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw VyronLocalAuthError.invalidConfiguration }
        defer { close(descriptor); unlinkat(directory, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw VyronLocalAuthError.invalidConfiguration }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, renameat(directory, temporary, directory, "pending-removals.json") == 0 else {
            throw VyronLocalAuthError.invalidConfiguration
        }
        guard fsync(directory) == 0 else { throw VyronLocalAuthError.invalidConfiguration }
    }
}
