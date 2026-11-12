import Foundation

struct VyronDevelopmentTaskState: Codable, Sendable, Equatable {
    let identity: VyronDevelopmentTaskIdentity
    private(set) var plan: [VyronDevelopmentPlanStep]
    private(set) var progress: VyronDevelopmentTaskProgress
    private(set) var lifecycle: VyronDevelopmentTaskLifecycle

    var guidance: [String] { progress.context.guidance }
    var status: VyronDevelopmentTaskStatus { lifecycle.status }

    init(identity: VyronDevelopmentTaskIdentity) {
        self.identity = identity
        plan = []
        progress = VyronDevelopmentTaskProgress()
        lifecycle = VyronDevelopmentTaskLifecycle(updatedAt: identity.startedAt)
    }

    init(continuing identity: VyronDevelopmentTaskIdentity, checkpoints: [Self]) throws {
        self.init(identity: identity)
        for checkpoint in checkpoints {
            try checkpoint.validate(projectPath: identity.projectPath)
            if !checkpoint.plan.isEmpty {
                let completed = Set(plan.filter { $0.status == .completed }.map(\.title))
                let nextCompleted = Set(checkpoint.plan.filter { $0.status == .completed }.map(\.title))
                guard completed.isSubset(of: nextCompleted) else {
                    throw Self.invalid(
                        "The continuation records disagree about completed plan stages. Review the saved tasks first."
                    )
                }
                plan = checkpoint.plan
            }
            for file in checkpoint.progress.files { try mergeContinuationFile(file) }
            for operation in checkpoint.progress.fileOperations { try recordFileOperation(operation) }
            for intent in checkpoint.progress.fileOperationIntents { try recordFileOperationIntent(intent) }
            try progress.fileEvidence.reconcile()
            for check in checkpoint.progress.checks where !progress.checks.contains(check) {
                progress.checks.append(check)
            }
            for integration in checkpoint.progress.integrations { try mergeContinuationIntegration(integration) }
            try mergeContinuationGuidance(checkpoint.guidance)
            progress.context.decisions.append(contentsOf: checkpoint.progress.context.decisions)
            if !checkpoint.progress.context.summary.isEmpty {
                progress.context.summary = checkpoint.progress.context.summary
            }
            if checkpoint.lifecycle.updatedAt > lifecycle.updatedAt { lifecycle = checkpoint.lifecycle }
        }
        progress.context.decisions = Array(progress.context.decisions.suffix(VyronDevelopmentTaskLimits.maximumDecisions))
        // Validate before persisting; do not silently trim file, check, action or user-guidance evidence.
        try validate(projectPath: identity.projectPath)
    }

    mutating func mergeContinuationGuidance(_ guidance: [String]) throws {
        let incoming = guidance.filter { !VyronDevelopmentContinuationContext.isContinuationRequest($0) }
        let existing = self.guidance.filter { !VyronDevelopmentContinuationContext.isContinuationRequest($0) }
        var shared = zip(existing, incoming).prefix { pair in pair.0 == pair.1 }.count
        if shared < existing.count {
            // App transcript guidance can be a tail following an older Core clarification representation.
            // Match ordered overlap rather than deduplicating values, which would erase revisions such as A, B, A.
            for count in stride(from: min(existing.count, incoming.count), through: 1, by: -1)
                where existing.suffix(count).elementsEqual(incoming.prefix(count)) {
                shared = max(shared, count)
                break
            }
        }
        for instruction in incoming.dropFirst(shared) { try recordGuidance(instruction) }
    }

    private mutating func mergeContinuationFile(_ file: VyronDevelopmentFileProgress) throws {
        if let previous = progress.files.first(where: { $0.path == file.path }) {
            if previous.recordedAt > file.recordedAt { return }
            guard previous.recordedAt != file.recordedAt || previous.contentHash == file.contentHash else {
                throw Self.invalid("The continuation has conflicting file evidence without a reliable order.")
            }
        }
        try recordFile(file)
    }

    private mutating func mergeContinuationIntegration(_ integration: VyronDevelopmentIntegrationProgress) throws {
        if let index = progress.integrations.firstIndex(where: { $0.identity == integration.identity }) {
            let previous = progress.integrations[index]
            if previous.recordedAt > integration.recordedAt { return }
            guard previous.recordedAt != integration.recordedAt || previous == integration else {
                throw Self.invalid("The continuation has conflicting action outcomes without a reliable order.")
            }
            progress.integrations[index] = integration
        } else {
            progress.integrations.append(integration)
        }
    }

    mutating func updatePlan(_ update: VyronDevelopmentPlanUpdate) throws {
        try Self.validatePlan(update.steps)
        plan = update.steps
        if let explanation = update.explanation { recordDecision(explanation) }
        touch()
    }

    mutating func recordFile(_ file: VyronDevelopmentFileProgress) throws {
        try Self.validateFile(file)
        guard progress.files.contains(where: { $0.path == file.path })
            || progress.files.count < VyronDevelopmentTaskLimits.maximumFiles else {
            throw Self.invalid("The saved file-evidence allowance is exhausted. Review the checkpoint before starting another task.")
        }
        let previous = progress.files.first { $0.path == file.path }
        let recorded: VyronDevelopmentFileProgress
        if let previous, previous.status == .saved, file.status == .unchanged {
            recorded = VyronDevelopmentFileProgress(
                path: file.path,
                contentHash: file.contentHash,
                status: .saved,
                recordedAt: previous.contentHash == file.contentHash ? previous.recordedAt : file.recordedAt
            )
        } else {
            recorded = file
        }
        progress.files.removeAll { $0.path == file.path }
        progress.files.append(recorded)
        touch()
    }

    mutating func recordCheck(_ check: VyronDevelopmentCheckProgress) throws {
        try Self.validateCheck(check)
        progress.checks.append(check)
        if progress.checks.count > VyronDevelopmentTaskLimits.maximumChecks { progress.checks.removeFirst() }
        touch()
    }

    mutating func recordFileOperation(_ operation: VyronDevelopmentFileOperationEvidence) throws {
        var evidence = progress.fileEvidence
        try evidence.record(operation)
        progress.fileEvidence = evidence
        touch()
    }

    mutating func recordFileOperationIntent(_ intent: VyronDevelopmentFileOperationIntent) throws {
        var evidence = progress.fileEvidence
        try evidence.recordIntent(intent)
        progress.fileEvidence = evidence
        touch()
    }

    mutating func recordIntegration(_ outcome: VyronDevelopmentIntegrationProgress) throws {
        try Self.validateIntegration(outcome)
        if let index = progress.integrations.firstIndex(where: { $0.identity == outcome.identity }) {
            progress.integrations[index] = outcome
        } else {
            guard progress.integrations.count < VyronDevelopmentTaskLimits.maximumIntegrations else {
                throw Self.invalid("The saved integration-action allowance is exhausted. Review completed actions before starting another task.")
            }
            progress.integrations.append(outcome)
        }
        touch()
    }

    mutating func recordGuidance(_ text: String) throws {
        guard VyronDevelopmentTaskText.isValid(text, maximumBytes: VyronDevelopmentTaskLimits.maximumGuidanceBytes),
            progress.context.guidance.count < VyronDevelopmentTaskLimits.maximumGuidanceEntries,
            progress.context.guidance.reduce(text.utf8.count, { $0 + $1.utf8.count })
                <= VyronDevelopmentTaskLimits.maximumGuidanceBytes
        else { throw Self.invalid("The task's saved user guidance exceeds its bounded storage allowance.") }
        progress.context.guidance.append(text)
        touch()
    }

    mutating func recordDecision(_ text: String) {
        let value = VyronDevelopmentTaskText.prefix(
            text.replacingOccurrences(of: "\0", with: ""),
            maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes
        )
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        progress.context.decisions.append(value)
        if progress.context.decisions.count > VyronDevelopmentTaskLimits.maximumDecisions {
            progress.context.decisions.removeFirst()
        }
        touch()
    }

    mutating func updateSummary(_ text: String) {
        progress.context.summary = VyronDevelopmentTaskText.prefix(
            text.replacingOccurrences(of: "\0", with: ""),
            maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes
        )
        touch()
    }

    mutating func finish(_ status: VyronDevelopmentTaskStatus, detail: String? = nil) {
        lifecycle.status = status
        lifecycle.detail = detail.map {
            VyronDevelopmentTaskText.prefix($0, maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes)
        }
        touch()
    }

    private mutating func touch() { lifecycle.updatedAt = max(lifecycle.updatedAt, Date()) }
}
