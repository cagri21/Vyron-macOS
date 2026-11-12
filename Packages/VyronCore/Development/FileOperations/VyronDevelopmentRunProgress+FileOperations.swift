import Foundation
import VyronDevelopment

extension VyronDevelopmentRunProgress {
    mutating func beginFileOperation(
        _ prepared: VyronPreparedProjectFileOperation,
        call: DevelopmentToolCall
    ) throws {
        try Task.checkCancellation()
        guard state.progress.fileOperations.count < VyronDevelopmentTaskLimits.maximumFileOperations else {
            throw VyronDevelopmentCheckpointFailure(detail: "The file-operation evidence allowance is exhausted.")
        }
        let identity = try fileOperationIdentity(call)
        let intent = VyronDevelopmentFileOperationIntent(
            id: prepared.id, identity: identity,
            paths: VyronProjectFileOperationPaths(
                sourcePath: prepared.sourcePath, destinationPath: prepared.destinationPath
            ),
            disposition: .pending
        )
        var candidate = state
        try candidate.recordFileOperationIntent(intent)
        try candidate.recordIntegration(fileOperationIntegration(
            identity, status: .started,
            summary: "The native file operation was prepared; reconcile its saved outcome before any retry."
        ))
        try preflightFileOperation(prepared, intent: intent, state: candidate)
        try persistFileOperationState(candidate)
    }

    func canRetryFileOperation(_ call: DevelopmentToolCall) throws -> Bool {
        let identity = try fileOperationIdentity(call)
        return state.progress.fileOperationIntents.last { $0.identity == identity }?.disposition == .notPerformed
    }

    mutating func declineFileOperation(_ call: DevelopmentToolCall) throws {
        let identity = try fileOperationIdentity(call)
        var candidate = state
        for intent in state.progress.fileOperationIntents where intent.identity == identity
            && [.pending, .notPerformed].contains(intent.disposition) {
            try candidate.recordFileOperationIntent(intent.finishing(.declined))
        }
        try candidate.recordIntegration(fileOperationIntegration(
            identity, status: .failed, summary: "The user declined this file operation. No item was changed."
        ))
        try persistFileOperationState(candidate)
    }

    mutating func applyFileOperation(_ result: VyronProjectFileOperationResult) throws {
        var candidate = state
        try apply(result, to: &candidate, recordedAt: Date())
        try persistFileOperationState(candidate)
    }

    mutating func reconcileFileOperations(in workspace: DevelopmentWorkspace) async throws {
        var candidate = state
        var changed = false
        for intent in state.progress.fileOperationIntents where intent.disposition == .pending {
            let recovery = try await workspace.fileOperationRecovery(id: intent.id)
            if let result = recovery.result {
                guard result.id == intent.id, result.paths == intent.paths else {
                    throw VyronDevelopmentCheckpointFailure(detail: "The native recovery result has another identity.")
                }
                try apply(result, to: &candidate, recordedAt: recovery.recordedAt)
                changed = true
            } else if recovery.disposition == .notPerformed {
                try candidate.recordFileOperationIntent(intent.finishing(.notPerformed))
                try candidate.recordIntegration(fileOperationIntegration(
                    intent.identity, status: .failed,
                    summary: "The native file operation did not change any item. A fresh review may retry it."
                ))
                changed = true
            } else if let preserved = recovery.preservedItemURL {
                let summary = boundedAgentPrefix(
                    "The file operation has an uncertain outcome. A preserved item is at "
                        + String(reflecting: preserved.path) + ". Inspect it before retrying.",
                    bytes: VyronDevelopmentTaskLimits.maximumSummaryBytes
                )
                let previous = candidate.progress.integrations.first { $0.identity == intent.identity }
                if previous?.summary != summary {
                    try candidate.recordIntegration(fileOperationIntegration(
                        intent.identity, status: .started, summary: summary
                    ))
                    changed = true
                }
            }
        }
        if changed { try persistFileOperationState(candidate) }
    }

    private func preflightFileOperation(
        _ prepared: VyronPreparedProjectFileOperation,
        intent: VyronDevelopmentFileOperationIntent,
        state: VyronDevelopmentTaskState
    ) throws {
        var prospective = state
        try prospective.recordFileOperation(VyronDevelopmentFileOperationEvidence(
            id: prepared.id, kind: prepared.kind,
            impact: .complete(VyronProjectFileOperationImpact(
                paths: intent.paths, affectedFilePaths: prepared.affectedFilePaths,
                isCaseSensitive: prepared.isCaseSensitive
            )),
            recordedAt: Date()
        ))
        try prospective.recordFileOperationIntent(intent.finishing(.completed))
        let archive = VyronDevelopmentTaskArchive(schemaVersion: 1, task: prospective)
        let bytes = try JSONEncoder().encode(archive).count
        guard bytes <= VyronDevelopmentTaskLimits.maximumStoredBytes
            - VyronDevelopmentTaskLimits.fileOperationOutcomeReserveBytes else {
            throw VyronDevelopmentCheckpointFailure(
                detail: "The file operation would exceed task recovery storage. No item was changed."
            )
        }
    }

    private func apply(
        _ result: VyronProjectFileOperationResult,
        to candidate: inout VyronDevelopmentTaskState,
        recordedAt: Date
    ) throws {
        if let previous = candidate.progress.fileOperations.first(where: { $0.id == result.id }) {
            guard previous.kind == result.kind, previous.paths == result.paths else {
                throw VyronDevelopmentCheckpointFailure(detail: "The file operation has conflicting saved outcomes.")
            }
        } else {
            try candidate.recordFileOperation(VyronDevelopmentFileOperationEvidence(
                id: result.id, kind: result.kind, impact: .complete(result.impact), recordedAt: recordedAt
            ))
        }
        if let intent = candidate.progress.fileOperationIntents.first(where: { $0.id == result.id }) {
            guard intent.paths == result.paths else {
                throw VyronDevelopmentCheckpointFailure(detail: "The native result does not match the prepared paths.")
            }
            try candidate.recordFileOperationIntent(intent.finishing(.completed))
            try candidate.recordIntegration(fileOperationIntegration(
                intent.identity, status: .succeeded,
                summary: VyronDevelopmentFileOperationOutput.summary(result)
            ))
        }
    }

    private func fileOperationIdentity(_ call: DevelopmentToolCall) throws -> VyronDevelopmentIntegrationIdentity {
        VyronDevelopmentIntegrationIdentity(
            toolName: call.function.name, argumentsHash: try VyronDevelopmentRunControl.callKey(call)
        )
    }

    private func fileOperationIntegration(
        _ identity: VyronDevelopmentIntegrationIdentity,
        status: VyronDevelopmentIntegrationStatus,
        summary: String
    ) -> VyronDevelopmentIntegrationProgress {
        VyronDevelopmentIntegrationProgress(
            identity: identity, status: status,
            summary: boundedAgentPrefix(summary, bytes: VyronDevelopmentTaskLimits.maximumSummaryBytes)
        )
    }

    private mutating func persistFileOperationState(_ candidate: VyronDevelopmentTaskState) throws {
        do {
            try store.save(candidate)
            state = candidate
        } catch let failure as VyronDevelopmentCheckpointFailure {
            throw failure
        } catch {
            throw VyronDevelopmentCheckpointFailure(detail: error.localizedDescription)
        }
    }
}
