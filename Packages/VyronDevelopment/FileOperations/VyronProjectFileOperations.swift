import Foundation

/// Owned by DevelopmentWorkspace's actor; synchronous native calls do not yield the actor during mutation.
final class VyronProjectFileOperations {
    let access: VyronProjectFileAccess
    let journal: VyronProjectFileOperationJournal
    private var trash: any VyronProjectFileTrashing = VyronNativeProjectFileTrash()
    private var prepared: [UUID: VyronPreparedProjectFileOperation] = [:]
    private var dispositions: [UUID: VyronProjectFileOperationDisposition] = [:]

    init(
        rootURL: URL,
        journalDirectory: URL,
        isAllowedComponent: @escaping @Sendable (String) -> Bool
    ) throws {
        access = try VyronProjectFileAccess(rootURL: rootURL, isAllowedComponent: isAllowedComponent)
        journal = VyronProjectFileOperationJournal(directoryURL: journalDirectory, rootPath: rootURL.path)
    }

    func configureTrash(_ adapter: any VyronProjectFileTrashing) { trash = adapter }

    func prepare(_ request: VyronProjectFileOperationRequest) throws -> VyronPreparedProjectFileOperation {
        try Task.checkCancellation()
        let request = try access.normalized(request)
        for record in try journal.records()
            where (record.phase == .started || record.phase == .uncertain) && record.result == nil {
            let previous = record.identity.operation.request.paths
            let current = request.paths
            let oldPaths = [previous.sourcePath] + (previous.destinationPath.map { [$0] } ?? [])
            let newPaths = [current.sourcePath] + (current.destinationPath.map { [$0] } ?? [])
            guard !oldPaths.contains(where: { old in newPaths.contains(where: {
                Self.overlaps(old, $0, isCaseSensitive: record.identity.operation.isCaseSensitive)
            }) }) else {
                let hint = try preservedItem(record).map { " Its preserved item is at " + $0.path + "." } ?? ""
                throw DevelopmentError(
                    "An earlier file operation has an uncertain outcome. Inspect its saved history." + hint
                )
            }
        }
        guard prepared.count < 128 else {
            throw DevelopmentError("Too many pending file-operation reviews. Finish the current response first.")
        }
        let operation = VyronPreparedProjectFileOperation(
            id: UUID(), request: request, snapshot: try access.snapshot(request), preparedAt: Date()
        )
        if operation.kind == .trash {
            let staging = try staging(for: operation)
            if let identity = operation.snapshot.entries.first?.identity {
                try staging.requireSameVolume(as: identity)
            }
        }
        prepared[operation.id] = operation
        dispositions[operation.id] = .notPerformed
        return operation
    }

    func perform(
        _ operation: VyronPreparedProjectFileOperation,
        archivedChanges: [DevelopmentChange]
    ) throws -> VyronProjectFileOperationResult {
        try Task.checkCancellation()
        guard prepared[operation.id] == operation else {
            throw DevelopmentError("Prepare and review this file operation again before performing it.")
        }
        guard try access.snapshot(operation.request) == operation.snapshot else {
            throw DevelopmentError("The files or destination changed after review. No item was changed.")
        }
        var record = VyronProjectFileJournalRecord(
            identity: VyronProjectFileJournalIdentity(rootPath: access.rootURL.path, operation: operation),
            phase: .started, result: nil, archivedChanges: archivedChanges
        )
        let staging: VyronProjectFileStaging?
        if operation.kind == .trash {
            let proposed = try self.staging(for: operation)
            if let identity = operation.snapshot.entries.first?.identity {
                try proposed.requireSameVolume(as: identity)
            }
            staging = proposed
            record.state.stagedURL = proposed.url
        } else {
            staging = nil
        }
        try journal.save(record)
        dispositions[operation.id] = .uncertain
        prepared.removeValue(forKey: operation.id)
        var mutationMayHaveOccurred = false
        var originalParent: VyronProjectFileParent?
        do {
            // Revalidate after the durable intent is saved, immediately before the native mutation.
            guard try access.snapshot(operation.request) == operation.snapshot else {
                throw DevelopmentError("The files or destination changed after review. No item was changed.")
            }
            try Task.checkCancellation()
            let recoveryURL: URL?
            switch operation.kind {
            case .move, .rename:
                try access.move(operation)
                mutationMayHaveOccurred = true
                recoveryURL = nil
            case .trash:
                guard let staging else { throw DevelopmentError("Private Trash staging is unavailable.") }
                originalParent = try access.stage(operation, in: staging)
                mutationMayHaveOccurred = true
                try access.validateStaged(operation, in: staging)
                try Task.checkCancellation()
                recoveryURL = try trash.trashItem(at: staging.url)
                guard !staging.containsItem() else {
                    throw DevelopmentError("The native Trash action did not move the staged item.")
                }
            }
            let result = VyronProjectFileOperationResult(
                id: operation.id, kind: operation.kind,
                impact: operation.impact,
                recoveryURL: recoveryURL
            )
            record.phase = .succeeded
            record.result = result
            record.state.updatedAt = Date()
            do {
                try journal.save(record)
            } catch {
                record.phase = .uncertain
                do { try journal.save(record) } catch {
                    throw DevelopmentError(
                        "The item changed, but its final history could not be saved. Do not repeat this operation."
                    )
                }
                throw DevelopmentError(
                    "The item changed, but its final history could not be confirmed. Inspect it before continuing."
                )
            }
            dispositions[operation.id] = .succeeded
            return result
        } catch {
            var recoveryDetail: String?
            if mutationMayHaveOccurred, let staging, let originalParent {
                do {
                    if try access.restoreStaged(operation, staging: staging, originalParent: originalParent) {
                        mutationMayHaveOccurred = false
                    }
                } catch {
                    recoveryDetail = "The item is preserved at " + staging.url.path
                        + ". Its original path could not be restored without replacing an item."
                }
            }
            record.phase = mutationMayHaveOccurred ? .uncertain : .notPerformed
            if record.result == nil { record.state.updatedAt = Date() }
            dispositions[operation.id] = mutationMayHaveOccurred ? .uncertain : .notPerformed
            do { try journal.save(record) } catch {
                throw DevelopmentError(
                    "The file operation could not be confirmed or its final history saved. Do not repeat it."
                )
            }
            if let recoveryDetail { throw DevelopmentError(recoveryDetail) }
            throw error
        }
    }

    func disposition(_ operation: VyronPreparedProjectFileOperation) -> VyronProjectFileOperationDisposition {
        dispositions[operation.id] ?? .uncertain
    }

    func recovery(id: UUID) throws -> VyronProjectFileOperationRecovery {
        guard let record = try journal.records().first(where: { $0.identity.operation.id == id }) else {
            return VyronProjectFileOperationRecovery(
                disposition: dispositions[id] ?? .uncertain,
                result: nil, recordedAt: .distantPast, preservedItemURL: nil
            )
        }
        let disposition: VyronProjectFileOperationDisposition
        switch record.phase {
        case .notPerformed: disposition = .notPerformed
        case .succeeded: disposition = .succeeded
        case .started, .uncertain: disposition = record.result == nil ? .uncertain : .succeeded
        }
        return VyronProjectFileOperationRecovery(
            disposition: disposition, result: record.result, recordedAt: record.state.updatedAt,
            preservedItemURL: try preservedItem(record)
        )
    }

    func discardPreparedReviews() { prepared.removeAll() }

    private func staging(for operation: VyronPreparedProjectFileOperation) throws -> VyronProjectFileStaging {
        try VyronProjectFileStaging(
            rootURL: journal.directoryURL.deletingLastPathComponent()
                .appendingPathComponent("FileOperationStaging", isDirectory: true),
            operationID: operation.id,
            name: (operation.sourcePath as NSString).lastPathComponent
        )
    }

    private func preservedItem(_ record: VyronProjectFileJournalRecord) throws -> URL? {
        let operation = record.identity.operation
        let expected = journal.directoryURL.deletingLastPathComponent()
            .appendingPathComponent("FileOperationStaging", isDirectory: true)
            .appendingPathComponent(operation.id.uuidString, isDirectory: true)
            .appendingPathComponent((operation.sourcePath as NSString).lastPathComponent)
        guard record.state.stagedURL == expected else { return nil }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: expected.path)
            let type = attributes[.type] as? FileAttributeType
            return type == .typeRegular || type == .typeDirectory ? expected : nil
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            return nil
        }
    }

    func shouldReconcile(_ record: VyronProjectFileJournalRecord) throws -> Bool {
        if record.phase == .succeeded || record.result != nil { return true }
        if record.phase == .notPerformed { return false }
        guard let identity = record.identity.operation.snapshot.entries.first?.identity else {
            throw DevelopmentError("The saved file operation has no source identity.")
        }
        return try !access.sourceMatchesIdentity(record.identity.operation.sourcePath, identity: identity)
    }

    private static func overlaps(_ first: String, _ second: String, isCaseSensitive: Bool) -> Bool {
        let forward = VyronProjectFileOperationImpact(
            paths: .init(sourcePath: first, destinationPath: nil),
            affectedFilePaths: [], isCaseSensitive: isCaseSensitive
        )
        let backward = VyronProjectFileOperationImpact(
            paths: .init(sourcePath: second, destinationPath: nil),
            affectedFilePaths: [], isCaseSensitive: isCaseSensitive
        )
        return forward.containsSource(second) || backward.containsSource(first)
    }
}
