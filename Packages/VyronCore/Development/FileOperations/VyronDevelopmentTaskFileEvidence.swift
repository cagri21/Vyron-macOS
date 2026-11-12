import Foundation

struct VyronDevelopmentTaskFileEvidence: Sendable, Equatable {
    var files: [VyronDevelopmentFileProgress] = []
    var operations: [VyronDevelopmentFileOperationEvidence] = []
    var intents: [VyronDevelopmentFileOperationIntent] = []

    mutating func recordIntent(_ intent: VyronDevelopmentFileOperationIntent) throws {
        try intent.validate()
        if let index = intents.firstIndex(where: { $0.id == intent.id }) {
            let old = intents[index]
            guard old.identity == intent.identity, old.paths == intent.paths,
                old.disposition == intent.disposition || old.disposition == .pending
                    || (old.disposition == .notPerformed && intent.disposition == .declined) else {
                throw VyronDevelopmentTaskState.invalid("The file operation has conflicting saved recovery metadata.")
            }
            intents[index] = intent
        } else {
            guard intents.count < VyronDevelopmentTaskLimits.maximumFileOperations else {
                throw VyronDevelopmentTaskState.invalid("The file-operation recovery allowance is exhausted.")
            }
            intents.append(intent)
        }
    }

    mutating func record(_ operation: VyronDevelopmentFileOperationEvidence) throws {
        try operation.validate()
        if let existing = operations.first(where: { $0.id == operation.id }) {
            guard existing == operation else {
                throw VyronDevelopmentTaskState.invalid("The saved file operation has conflicting outcomes.")
            }
        } else {
            guard operations.count < VyronDevelopmentTaskLimits.maximumFileOperations else {
                throw VyronDevelopmentTaskState.invalid("The file-operation evidence allowance is exhausted.")
            }
            operations.append(operation)
        }
        try reconcile()
    }

    mutating func reconcile() throws {
        let ordered = operations.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        for pair in zip(ordered, ordered.dropFirst()) where pair.0.recordedAt == pair.1.recordedAt {
            throw VyronDevelopmentTaskState.invalid("File operations disagree without a reliable execution order.")
        }
        var current = files
        for operation in ordered {
            try operation.validate()
            current = try remapped(current, through: operation)
        }
        files = current
        operations = ordered
    }

    private func remapped(
        _ files: [VyronDevelopmentFileProgress],
        through operation: VyronDevelopmentFileOperationEvidence
    ) throws -> [VyronDevelopmentFileProgress] {
        var mapped: [String: VyronDevelopmentFileProgress] = [:]
        for file in files {
            let matches = operation.containsSource(file.path)
            let next: VyronDevelopmentFileProgress
            if matches && file.recordedAt < operation.recordedAt {
                guard let destination = operation.relocatedPath(file.path) else { continue }
                next = VyronDevelopmentFileProgress(
                    path: destination,
                    contentHash: file.contentHash, status: file.status, recordedAt: operation.recordedAt
                )
            } else {
                next = file
            }
            try VyronDevelopmentTaskState.validateFile(next)
            if let existing = mapped[next.path] {
                guard existing.recordedAt != next.recordedAt || existing.contentHash == next.contentHash else {
                    throw VyronDevelopmentTaskState.invalid("The moved file has conflicting saved content evidence.")
                }
                if existing.recordedAt > next.recordedAt { continue }
                let status: VyronDevelopmentFileStatus = existing.status == .saved || next.status == .saved
                    ? .saved : .unchanged
                mapped[next.path] = VyronDevelopmentFileProgress(
                    path: next.path, contentHash: next.contentHash, status: status, recordedAt: next.recordedAt
                )
            } else {
                mapped[next.path] = next
            }
        }
        return mapped.values.sorted { $0.path < $1.path }
    }
}
