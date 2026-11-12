import Foundation

public struct VyronScheduledTask: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var definition: VyronScheduledTaskDefinition
    public var schedule: VyronTaskSchedule
    public var progress: VyronScheduledTaskProgress

    public init(
        id: UUID,
        definition: VyronScheduledTaskDefinition,
        schedule: VyronTaskSchedule,
        progress: VyronScheduledTaskProgress
    ) {
        self.id = id
        self.definition = definition
        self.schedule = schedule
        self.progress = progress
    }

    public func validated() throws -> Self {
        _ = try schedule.validated()
        let title = definition.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= VyronScheduledTaskLimits.titleCharacters,
            !definition.title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            !definition.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            definition.prompt.utf8.count <= VyronScheduledTaskLimits.promptBytes,
            definition.context.model.model.utf8.count <= VyronScheduledTaskLimits.modelBytes,
            !definition.context.model.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw VyronScheduledTaskError.invalidTask }

        if definition.context.mode != .chat {
            guard definition.context.workspacePath != nil,
                definition.prompt.count <= VyronScheduledTaskLimits.agentPromptCharacters
            else {
                throw VyronScheduledTaskError.invalidTask
            }
        }

        for path in [definition.context.workspacePath, definition.context.projectPath].compactMap({ $0 }) {
            guard path.hasPrefix("/"), path.utf8.count <= VyronScheduledTaskLimits.pathBytes,
                !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw VyronScheduledTaskError.invalidTask }
        }
        if let nextRun = progress.nextRunAt {
            guard nextRun.timeIntervalSinceReferenceDate.isFinite, nextRun >= schedule.startsAt else {
                throw VyronScheduledTaskError.invalidTask
            }
        }
        if let run = progress.lastRun {
            guard run.scheduledAt.timeIntervalSinceReferenceDate.isFinite,
                run.output.startedAt.timeIntervalSinceReferenceDate.isFinite,
                (run.output.detail?.utf8.count ?? 0) <= VyronScheduledTaskLimits.detailBytes
            else { throw VyronScheduledTaskError.invalidTask }
            if let finishedAt = run.output.finishedAt {
                guard finishedAt.timeIntervalSinceReferenceDate.isFinite, finishedAt >= run.output.startedAt else {
                    throw VyronScheduledTaskError.invalidTask
                }
            }
        }
        return self
    }
}
