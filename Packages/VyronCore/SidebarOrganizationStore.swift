import Darwin
import Foundation

/// A dedicated private local file, separate from chat history. Corrupt originals are never replaced.
public struct SidebarOrganizationStore: Sendable {
    public let fileURL: URL
    public static var defaultFileURL: URL {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("VyronAI/sidebar.json")
    }

    public init(fileURL: URL? = nil) { self.fileURL = fileURL ?? Self.defaultFileURL }

    public func load() throws -> SidebarOrganization? {
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 2_097_152
            else {
                throw SidebarOrganizationError.invalidOrganization("The saved file is not a bounded regular file.")
            }
            return try JSONDecoder().decode(SidebarOrganization.self, from: Data(contentsOf: fileURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch { throw SidebarOrganizationError.unreadableStore(error.localizedDescription) }
    }

    public func save(_ organization: SidebarOrganization) throws {
        try organization.validate()
        _ = try load()  // A failed prior read must never silently become an empty replacement.
        let directory = fileURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".sidebar-" + UUID().uuidString + ".tmp")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(organization)
            guard data.count <= 2_097_152 else {
                throw SidebarOrganizationError.invalidOrganization("The sidebar exceeds its storage budget.")
            }
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw SidebarOrganizationError.writeFailed("The private storage directory is invalid.")
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            guard
                FileManager.default.createFile(
                    atPath: temporary.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            else { throw SidebarOrganizationError.writeFailed("A private temporary file could not be created.") }
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
            guard Darwin.rename(temporary.path, fileURL.path) == 0 else {
                throw SidebarOrganizationError.writeFailed(String(cString: strerror(errno)))
            }
        } catch { throw SidebarOrganizationError.writeFailed(error.localizedDescription) }
    }
}
