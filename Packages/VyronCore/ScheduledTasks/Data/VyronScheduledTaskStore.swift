import Darwin
import Foundation

/// A versioned private store, independent of conversation history. Invalid originals cannot be overwritten.
public struct VyronScheduledTaskStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [VyronScheduledTask] {
        let data: Data
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                (values.fileSize ?? Int.max) <= VyronScheduledTaskLimits.storeBytes
            else { throw VyronScheduledTaskError.invalidStore }
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        let archive = try JSONDecoder().decode(VyronScheduledTaskArchive.self, from: data)
        guard archive.version == 1 else { throw VyronScheduledTaskError.unsupportedVersion }
        try validate(archive.tasks)
        return archive.tasks
    }

    public func save(_ tasks: [VyronScheduledTask]) throws {
        try validate(tasks)
        _ = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(VyronScheduledTaskArchive(tasks: tasks))
        guard data.count <= VyronScheduledTaskLimits.storeBytes else { throw VyronScheduledTaskError.invalidStore }

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw VyronScheduledTaskError.invalidStore
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let temporary = directory.appendingPathComponent(".scheduled-tasks-" + UUID().uuidString + ".tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else { throw VyronScheduledTaskError.storeUnavailable }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                do {
                    try handle.close()
                } catch let closeError {
                    throw NSError(
                        domain: NSCocoaErrorDomain,
                        code: CocoaError.fileWriteUnknown.rawValue,
                        userInfo: [NSMultipleUnderlyingErrorsKey: [error, closeError]]
                    )
                }
                throw error
            }
            guard Darwin.rename(temporary.path, fileURL.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            do {
                try FileManager.default.removeItem(at: temporary)
            } catch let cleanupError {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: CocoaError.fileWriteUnknown.rawValue,
                    userInfo: [NSMultipleUnderlyingErrorsKey: [error, cleanupError]]
                )
            }
            throw error
        }
    }

    private func validate(_ tasks: [VyronScheduledTask]) throws {
        guard tasks.count <= VyronScheduledTaskLimits.taskCount,
            Set(tasks.map(\.id)).count == tasks.count
        else { throw VyronScheduledTaskError.invalidStore }
        for task in tasks { _ = try task.validated() }
    }
}
