import Darwin
import Foundation

struct VyronNotificationReadStore: Sendable {
    let fileURL: URL

    init(fileURL: URL) { self.fileURL = fileURL.standardizedFileURL }

    func load() throws -> VyronNotificationReadState? {
        guard fileURL.isFileURL, fileURL.path.hasPrefix("/"),
            fileURL.deletingLastPathComponent().path != "/" else {
            throw VyronNotificationReadError.invalidStore
        }
        guard try validateDirectory(create: false) else { return nil }
        guard let attributes = try attributes(at: fileURL) else { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
            let bytes = attributes[.size] as? NSNumber,
            bytes.intValue <= VyronNotificationLimits.maximumStoredBytes else {
            throw VyronNotificationReadError.invalidStore
        }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= VyronNotificationLimits.maximumStoredBytes else {
            throw VyronNotificationReadError.invalidStore
        }
        return try JSONDecoder().decode(VyronNotificationReadState.self, from: data)
    }

    func save(_ state: VyronNotificationReadState) throws {
        try state.validate()
        _ = try load() // Corrupt originals must never be replaced by an empty or partial read state.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= VyronNotificationLimits.maximumStoredBytes else {
            throw VyronNotificationReadError.capacityExceeded
        }
        _ = try validateDirectory(create: true)
        let temporary = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".notification-read-" + UUID().uuidString + ".tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]
        ) else { throw VyronNotificationReadError.invalidStore }
        do {
            try data.write(to: temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                do {
                    try handle.close()
                } catch let closeError {
                    throw NSError(
                        domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
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
                    domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                    userInfo: [NSMultipleUnderlyingErrorsKey: [error, cleanupError]]
                )
            }
            throw error
        }
    }

    private func validateDirectory(create: Bool) throws -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        var ancestor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in directory.pathComponents.dropFirst() {
            ancestor.appendPathComponent(component, isDirectory: true)
            if let attributes = try attributes(at: ancestor) {
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw VyronNotificationReadError.invalidStore
                }
            }
        }
        if let attributes = try attributes(at: directory) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw VyronNotificationReadError.invalidStore
            }
            return true
        }
        guard create else { return false }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        guard let attributes = try attributes(at: directory),
            attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw VyronNotificationReadError.invalidStore
        }
        return true
    }

    /// Foundation's native metadata dictionary stays confined to this filesystem boundary.
    private func attributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return nil }
    }
}
