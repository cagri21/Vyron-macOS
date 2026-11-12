import Foundation

extension VyronDevelopmentTaskState {
    func validate(projectPath: String) throws {
        guard identity.projectPath == projectPath,
            identity.projectPath.hasPrefix("/"),
            VyronDevelopmentTaskText.isValid(identity.projectPath, maximumBytes: 4_096),
            VyronDevelopmentTaskText.isValid(
                identity.originalGoal, maximumBytes: VyronDevelopmentTaskLimits.maximumGoalBytes
            ),
            identity.startedAt.timeIntervalSince1970.isFinite,
            lifecycle.updatedAt.timeIntervalSince1970.isFinite,
            lifecycle.detail.map({
                VyronDevelopmentTaskText.isValid(
                    $0, maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes, permitsEmpty: true
                )
            }) ?? true
        else { throw Self.invalid("The saved task has an invalid project, goal, or lifecycle.") }
        try Self.validatePlan(plan, permitsEmpty: true)
        guard progress.files.count <= VyronDevelopmentTaskLimits.maximumFiles,
            Set(progress.files.map(\.path)).count == progress.files.count,
            progress.checks.count <= VyronDevelopmentTaskLimits.maximumChecks,
            progress.integrations.count <= VyronDevelopmentTaskLimits.maximumIntegrations,
            progress.fileOperations.count <= VyronDevelopmentTaskLimits.maximumFileOperations,
            Set(progress.fileOperations.map(\.id)).count == progress.fileOperations.count,
            progress.fileOperationIntents.count <= VyronDevelopmentTaskLimits.maximumFileOperations,
            Set(progress.fileOperationIntents.map(\.id)).count == progress.fileOperationIntents.count,
            guidance.count <= VyronDevelopmentTaskLimits.maximumGuidanceEntries,
            guidance.reduce(0, { $0 + $1.utf8.count }) <= VyronDevelopmentTaskLimits.maximumGuidanceBytes,
            guidance.allSatisfy({
                VyronDevelopmentTaskText.isValid($0, maximumBytes: VyronDevelopmentTaskLimits.maximumGuidanceBytes)
            }),
            progress.context.decisions.count <= VyronDevelopmentTaskLimits.maximumDecisions,
            progress.context.decisions.allSatisfy({
                VyronDevelopmentTaskText.isValid($0, maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes)
            }),
            VyronDevelopmentTaskText.isValid(
                progress.context.summary,
                maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes,
                permitsEmpty: true
            )
        else { throw Self.invalid("The saved task contains invalid or oversized progress evidence.") }
        try progress.files.forEach(Self.validateFile)
        try progress.checks.forEach(Self.validateCheck)
        try progress.integrations.forEach(Self.validateIntegration)
        try progress.fileOperations.forEach { try $0.validate() }
        try progress.fileOperationIntents.forEach { try $0.validate() }
    }

    static func validatePlan(_ steps: [VyronDevelopmentPlanStep], permitsEmpty: Bool = false) throws {
        guard (permitsEmpty || !steps.isEmpty), steps.count <= VyronDevelopmentTaskLimits.maximumPlanSteps,
            Set(steps.map(\.title)).count == steps.count,
            steps.filter({ $0.status == .inProgress }).count <= 1,
            steps.allSatisfy({
                VyronDevelopmentTaskText.isValid($0.title, maximumBytes: VyronDevelopmentTaskLimits.maximumStepBytes)
            })
        else { throw invalid("Provide one to twelve distinct bounded plan steps, with at most one in progress.") }
    }

    static func validateFile(_ file: VyronDevelopmentFileProgress) throws {
        let components = file.path.split(separator: "/", omittingEmptySubsequences: false)
        guard VyronDevelopmentTaskText.isValid(file.path, maximumBytes: 4_096),
            !file.path.hasPrefix("/"), !components.isEmpty,
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
            file.contentHash.count == 64,
            file.contentHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            file.recordedAt.timeIntervalSince1970.isFinite
        else { throw invalid("The task's file evidence has an unsafe path or invalid content hash.") }
    }

    static func validateCheck(_ check: VyronDevelopmentCheckProgress) throws {
        guard VyronDevelopmentTaskText.isValid(check.command, maximumBytes: 2_000),
            VyronDevelopmentTaskText.isValid(
                check.summary, maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes, permitsEmpty: true
            ), check.recordedAt.timeIntervalSince1970.isFinite
        else { throw invalid("The task's command evidence is invalid or oversized.") }
    }

    static func validateIntegration(_ outcome: VyronDevelopmentIntegrationProgress) throws {
        guard VyronDevelopmentTaskText.isValid(outcome.toolName, maximumBytes: 256),
            outcome.argumentsHash.count == 64,
            outcome.argumentsHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            VyronDevelopmentTaskText.isValid(
                outcome.summary, maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes, permitsEmpty: true
            ), outcome.recordedAt.timeIntervalSince1970.isFinite
        else { throw invalid("The task's integration evidence is invalid or oversized.") }
    }

    static func invalid(_ message: String) -> VyronDevelopmentTaskStateError {
        VyronDevelopmentTaskStateError(message: message)
    }
}
