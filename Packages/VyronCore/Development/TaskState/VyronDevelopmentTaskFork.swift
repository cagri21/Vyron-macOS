import Foundation
import VyronDevelopment

/// An explicit user-created chat fork may copy verified task evidence into a new owner.
/// This carries no command approval or provider authority, and cannot choose arbitrary source checkpoints.
public struct VyronDevelopmentTaskFork: Sendable {
    private let state: VyronDevelopmentTaskState
    private let store: VyronDevelopmentTaskStore

    public static func prepare(
        workspace: DevelopmentWorkspace,
        source: VyronDevelopmentSessionContext,
        destination: VyronDevelopmentSessionContext
    ) throws -> Self? {
        try Task.checkCancellation()
        guard source.conversationID != destination.conversationID,
            let context = source.continuation else {
            throw DevelopmentAgentError.invalidTool("Choose a different chat and verified task history for the fork.")
        }
        let sourceStore = try VyronDevelopmentTaskStore(
            directoryURL: workspace.taskStateDirectoryURL.appendingPathComponent(source.conversationID.uuidString),
            projectPath: workspace.rootURL.path
        )
        guard let original = try sourceStore.taskForExplicitFork(context) else { return nil }
        let destinationStore = try VyronDevelopmentTaskStore(
            directoryURL: workspace.taskStateDirectoryURL.appendingPathComponent(destination.conversationID.uuidString),
            projectPath: workspace.rootURL.path
        )
        guard try destinationStore.load(id: destination.responseID) == nil else {
            throw DevelopmentAgentError.invalidTool("The new chat already has a task checkpoint; it was preserved.")
        }
        let identity = VyronDevelopmentTaskIdentity(
            id: destination.responseID,
            projectPath: workspace.rootURL.path,
            originalGoal: original.identity.originalGoal,
            startedAt: original.identity.startedAt
        )
        var copied = try VyronDevelopmentTaskState(continuing: identity, checkpoints: [original])
        try copied.mergeContinuationGuidance(context.guidance)
        copied.finish(
            original.status.isFinished ? .completed : .interrupted,
            detail: original.status.isFinished ? original.lifecycle.detail
                : "Forked by the user. Verify current files before continuing; do not replay actions."
        )
        return Self(state: copied, store: destinationStore)
    }

    public func save() throws {
        try Task.checkCancellation()
        guard try store.load(id: state.identity.id) == nil else {
            throw DevelopmentAgentError.invalidTool("The new chat already has a task checkpoint; it was preserved.")
        }
        try store.save(state)
    }

    /// Rollback removes only this exact newly created checkpoint, never another task or the source history.
    public func removeCreatedCheckpoint() throws {
        try store.removeCreatedFork(state)
    }
}
