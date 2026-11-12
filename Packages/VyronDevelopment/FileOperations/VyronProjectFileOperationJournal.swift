import Foundation

/// Separate records preserve the existing content-change journal schema and backups.
final class VyronProjectFileOperationJournal {
    let directoryURL: URL
    private let rootPath: String

    init(directoryURL: URL, rootPath: String) {
        self.directoryURL = directoryURL
        self.rootPath = rootPath
    }

    func records() throws -> [VyronProjectFileJournalRecord] {
        guard try prepareDirectory(create: false) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        guard urls.count <= VyronProjectFileOperationLimits.maximumRecords else {
            throw DevelopmentError("The file-operation history exceeds its bounded storage allowance.")
        }
        _ = try historyBytes(urls)
        return try urls.filter { $0.pathExtension == "json" }.map { url in
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                throw DevelopmentError("The file-operation history contains an invalid record.")
            }
            return try load(id)
        }.sorted { $0.identity.operation.preparedAt < $1.identity.operation.preparedAt }
    }

    func load(_ id: UUID) throws -> VyronProjectFileJournalRecord {
        let url = fileURL(id)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? NSNumber,
            size.intValue <= VyronProjectFileOperationLimits.maximumStoredBytes else {
            throw DevelopmentError("File-operation history must be a bounded regular file, not a symbolic link.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= VyronProjectFileOperationLimits.maximumStoredBytes else {
            throw DevelopmentError("The file-operation history record is oversized.")
        }
        let record = try JSONDecoder().decode(VyronProjectFileJournalRecord.self, from: data)
        guard record.identity.rootPath == rootPath, record.identity.operation.id == id else {
            throw DevelopmentError("The file-operation history belongs to a different project or operation.")
        }
        try validate(record)
        return record
    }

    func save(_ record: VyronProjectFileJournalRecord) throws {
        guard record.identity.rootPath == rootPath else {
            throw DevelopmentError("The file operation belongs to a different project.")
        }
        let data = try JSONEncoder().encode(record)
        guard data.count <= VyronProjectFileOperationLimits.maximumStoredBytes else {
            throw DevelopmentError("The file-operation history exceeds its bounded storage allowance.")
        }
        _ = try prepareDirectory(create: true)
        let url = fileURL(record.identity.operation.id)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        let exists = urls.contains(url)
        guard exists || urls.count < VyronProjectFileOperationLimits.maximumRecords else {
            throw DevelopmentError("The file-operation history is full. No item was changed.")
        }
        if exists { _ = try load(record.identity.operation.id) }
        let retainedBytes = try historyBytes(urls.filter { $0 != url })
        guard retainedBytes <= VyronProjectFileOperationLimits.maximumHistoryBytes - data.count else {
            throw DevelopmentError("The file-operation history is full. No new operation can start.")
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func fileURL(_ id: UUID) -> URL {
        directoryURL.appendingPathComponent(id.uuidString + ".json")
    }

    private func validate(_ record: VyronProjectFileJournalRecord) throws {
        let operation = record.identity.operation
        guard validPath(operation.sourcePath), operation.destinationPath.map(validPath) != false,
            !operation.snapshot.entries.isEmpty,
            operation.snapshot.entries.count <= VyronProjectFileOperationLimits.maximumEntries,
            operation.snapshot.entries.first?.relativePath == "",
            operation.snapshot.entries.allSatisfy({ $0.relativePath.isEmpty || validPath($0.relativePath) }),
            record.archivedChanges.count <= VyronProjectFileOperationLimits.maximumEntries,
            record.archivedChanges.allSatisfy({ change in
                validPath(change.path) && operation.impact.containsSource(change.path)
                    && change.after.utf8.count <= 512_000 && (change.before?.utf8.count ?? 0) <= 512_000
            }),
            record.phase != .succeeded || record.result != nil else {
            throw DevelopmentError("The file-operation history contains invalid paths or incomplete evidence.")
        }
        if let result = record.result {
            guard result.id == operation.id, result.kind == operation.kind, result.paths == operation.request.paths,
                result.affectedFilePaths.allSatisfy(validPath), result.recoveryURL?.isFileURL != false else {
                throw DevelopmentError("The file-operation result does not match its reviewed request.")
            }
        }
    }

    private func validPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && path.utf8.count <= 4_096
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
                    && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            }
    }

    private func historyBytes(_ urls: [URL]) throws -> Int {
        var total = 0
        for url in urls {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                let size = attributes[.size] as? NSNumber, size.intValue >= 0,
                size.intValue <= VyronProjectFileOperationLimits.maximumHistoryBytes - total else {
                throw DevelopmentError("The file-operation history is unsafe or exceeds its storage allowance.")
            }
            total += size.intValue
        }
        return total
    }

    private func prepareDirectory(create: Bool) throws -> Bool {
        var missing: [URL] = []
        var cursor = directoryURL
        while cursor.path != "/" {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: cursor.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw DevelopmentError("File-operation history directories must not contain symbolic links.")
                }
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                missing.append(cursor)
            }
            cursor.deleteLastPathComponent()
        }
        guard create || missing.isEmpty else { return false }
        for url in missing.reversed() {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
            )
        }
        return true
    }
}
