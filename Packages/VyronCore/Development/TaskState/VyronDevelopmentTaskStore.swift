import Foundation

/// Separate task checkpoints; the existing workspace changes.json schema remains untouched.
struct VyronDevelopmentTaskStore: Sendable {
    let directoryURL: URL
    let projectPath: String

    init(directoryURL: URL, projectPath: String) throws {
        guard directoryURL.isFileURL, directoryURL.path.hasPrefix("/"), directoryURL.path != "/",
            projectPath.hasPrefix("/"), VyronDevelopmentTaskText.isValid(projectPath, maximumBytes: 4_096)
        else { throw VyronDevelopmentTaskState.invalid("Choose a specific local task checkpoint directory and project.") }
        self.directoryURL = directoryURL.standardizedFileURL
        self.projectPath = projectPath
    }

    func save(_ state: VyronDevelopmentTaskState) throws {
        try state.validate(projectPath: projectPath)
        let data = try JSONEncoder().encode(VyronDevelopmentTaskArchive(schemaVersion: 1, task: state))
        guard data.count <= VyronDevelopmentTaskLimits.maximumStoredBytes else {
            throw VyronDevelopmentTaskState.invalid("The task checkpoint exceeds its bounded storage allowance.")
        }
        _ = try prepareDirectory(create: true)
        // Read and validate an existing record before replacing it; preserve corruption for diagnosis.
        _ = try load(id: state.identity.id)
        let url = fileURL(id: state.identity.id)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func load(id: UUID) throws -> VyronDevelopmentTaskState? {
        guard try prepareDirectory(create: false) else { return nil }
        let url = fileURL(id: id)
        guard let attributes = try attributes(at: url) else { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
            let size = attributes[.size] as? NSNumber,
            size.intValue <= VyronDevelopmentTaskLimits.maximumStoredBytes
        else { throw VyronDevelopmentTaskState.invalid("Task history must be a bounded regular file, not a symbolic link.") }
        let data = try Data(contentsOf: url)
        guard data.count <= VyronDevelopmentTaskLimits.maximumStoredBytes else {
            throw VyronDevelopmentTaskState.invalid("The saved task checkpoint is oversized.")
        }
        let archive = try JSONDecoder().decode(VyronDevelopmentTaskArchive.self, from: data)
        guard archive.schemaVersion == 1, archive.task.identity.id == id else {
            throw VyronDevelopmentTaskState.invalid("The saved task checkpoint has an invalid version or identity.")
        }
        try archive.task.validate(projectPath: projectPath)
        return archive.task
    }

    func latestUnfinished(goal: String? = nil) throws -> VyronDevelopmentTaskState? {
        try unfinishedTasks().filter { goal == nil || $0.identity.originalGoal == goal }
            .max { $0.lifecycle.updatedAt < $1.lifecycle.updatedAt }
    }

    func unfinishedTasks() throws -> [VyronDevelopmentTaskState] {
        try taskRecords().filter { !$0.status.isFinished }
    }

    func continuationTask(_ context: VyronDevelopmentContinuationContext) throws -> VyronDevelopmentTaskState? {
        try verifiedTask(context, requireUnfinished: true)
    }

    func taskForExplicitFork(_ context: VyronDevelopmentContinuationContext) throws -> VyronDevelopmentTaskState? {
        try verifiedTask(context, requireUnfinished: false)
    }

    private func verifiedTask(
        _ context: VyronDevelopmentContinuationContext,
        requireUnfinished: Bool
    ) throws -> VyronDevelopmentTaskState? {
        let context = try context.validated()
        var seen: Set<UUID> = []
        var records: [VyronDevelopmentTaskState] = []
        for id in context.priorResponseIDs where seen.insert(id).inserted {
            try Task.checkCancellation()
            if let record = try load(id: id) { records.append(record) }
        }
        guard !records.isEmpty else { return nil }
        let substantive = records.filter {
            !VyronDevelopmentContinuationContext.isContinuationRequest($0.identity.originalGoal)
        }
        let originalGoal = context.originalGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard substantive.allSatisfy({ $0.identity.originalGoal == originalGoal }) else {
            throw DevelopmentAgentError.invalidTool(
                "The verified continuation history contains different original tasks. Name the task to continue."
            )
        }
        guard let target = substantive.first ?? records.last else { return nil }
        let ordered = try orderedContinuationRecords(records)
        guard let latest = ordered.last else { return nil }
        guard !requireUnfinished || !latest.status.isFinished else {
            throw DevelopmentAgentError.invalidTool(
                "The referenced task is already complete. Describe the additional work before starting it again."
            )
        }
        let identity = VyronDevelopmentTaskIdentity(
            id: target.identity.id, projectPath: projectPath,
            originalGoal: originalGoal, startedAt: target.identity.startedAt
        )
        var merged = try VyronDevelopmentTaskState(continuing: identity, checkpoints: ordered)
        if !requireUnfinished { merged.finish(latest.status, detail: latest.lifecycle.detail) }
        return merged
    }

    func removeCreatedFork(_ expected: VyronDevelopmentTaskState) throws {
        guard let existing = try load(id: expected.identity.id) else { return }
        guard existing == expected else {
            throw VyronDevelopmentTaskState.invalid("The forked checkpoint changed; it was preserved for review.")
        }
        try FileManager.default.removeItem(at: fileURL(id: expected.identity.id))
    }

    private func orderedContinuationRecords(
        _ records: [VyronDevelopmentTaskState]
    ) throws -> [VyronDevelopmentTaskState] {
        let ordered = records.sorted {
            if $0.lifecycle.updatedAt != $1.lifecycle.updatedAt { return $0.lifecycle.updatedAt < $1.lifecycle.updatedAt }
            return $0.identity.id.uuidString < $1.identity.id.uuidString
        }
        for (earlier, later) in zip(ordered, ordered.dropFirst())
            where earlier.lifecycle.updatedAt == later.lifecycle.updatedAt {
            let earlierGuidance = earlier.guidance.filter {
                !VyronDevelopmentContinuationContext.isContinuationRequest($0)
            }
            let laterGuidance = later.guidance.filter {
                !VyronDevelopmentContinuationContext.isContinuationRequest($0)
            }
            guard earlier.status == later.status, earlier.plan == later.plan, earlierGuidance == laterGuidance,
                earlier.progress.context.summary == later.progress.context.summary,
                earlier.progress.context.decisions == later.progress.context.decisions else {
                throw VyronDevelopmentTaskState.invalid(
                    "The continuation checkpoints disagree without a reliable update order. Review the saved tasks first."
                )
            }
        }
        return ordered
    }

    private func taskRecords() throws -> [VyronDevelopmentTaskState] {
        guard try prepareDirectory(create: false) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )
        guard urls.count <= 4_096 else {
            throw VyronDevelopmentTaskState.invalid("The task history contains too many records to inspect safely.")
        }
        var records: [VyronDevelopmentTaskState] = []
        for url in urls where url.pathExtension == "json" {
            try Task.checkCancellation()
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                let state = try load(id: id)
            else { continue }
            records.append(state)
        }
        return records
    }

    private func fileURL(id: UUID) -> URL { directoryURL.appendingPathComponent(id.uuidString + ".json") }

    private func prepareDirectory(create: Bool) throws -> Bool {
        var missing: [URL] = []
        var cursor = directoryURL
        while cursor.path != "/" {
            if let values = try attributes(at: cursor) {
                guard values[.type] as? FileAttributeType == .typeDirectory else {
                    throw VyronDevelopmentTaskState.invalid("Task history directories must not contain symbolic links.")
                }
            } else {
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

    /// FileManager's native metadata dictionary is confined to this filesystem boundary.
    private func attributes(at url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
            return nil
        }
    }
}
