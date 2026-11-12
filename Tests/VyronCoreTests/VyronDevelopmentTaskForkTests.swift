import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentTaskForkTests: XCTestCase {
    func testExplicitForkPreservesPlanFilesChecksAndUncertainActionLedgerInNewOwner() throws {
        let workspace = try workspace()
        let sourceOwner = UUID()
        let original = try task(workspace: workspace)
        let sourceStore = try store(workspace: workspace, owner: sourceOwner)
        try sourceStore.save(original)
        let sourceData = try Data(contentsOf: checkpoint(workspace, owner: sourceOwner, id: original.identity.id))
        let destination = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let source = session(owner: sourceOwner, task: original)

        let fork = try XCTUnwrap(VyronDevelopmentTaskFork.prepare(
            workspace: workspace, source: source, destination: destination
        ))
        let destinationStore = try store(workspace: workspace, owner: destination.conversationID)
        XCTAssertNil(try destinationStore.load(id: destination.responseID))
        try fork.save()
        let copied = try XCTUnwrap(destinationStore.load(id: destination.responseID))
        XCTAssertEqual(copied.identity.id, destination.responseID)
        XCTAssertEqual(copied.identity.originalGoal, original.identity.originalGoal)
        XCTAssertEqual(copied.identity.startedAt, original.identity.startedAt)
        XCTAssertEqual(copied.status, .interrupted)
        XCTAssertEqual(copied.plan, original.plan)
        XCTAssertEqual(copied.progress.files, original.progress.files)
        XCTAssertEqual(copied.progress.checks, original.progress.checks)
        XCTAssertEqual(copied.progress.integrations, original.progress.integrations)
        XCTAssertEqual(copied.guidance, original.guidance)
        XCTAssertEqual(
            try Data(contentsOf: checkpoint(workspace, owner: sourceOwner, id: original.identity.id)), sourceData
        )

        let progress = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: destination.conversationID,
                responseID: UUID(),
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: original.identity.originalGoal, priorResponseIDs: [destination.responseID]
                )
            ),
            goal: "Continue"
        )
        XCTAssertEqual(progress.state.identity.id, destination.responseID)
        XCTAssertEqual(progress.state.progress.integrations, original.progress.integrations)
    }

    func testCompletedForkRejectsBareContinueWithoutWritesAndDoesNotCopyUnrelatedTasks() throws {
        let workspace = try workspace()
        let owner = UUID()
        let sourceStore = try store(workspace: workspace, owner: owner)
        var completed = try task(workspace: workspace)
        completed.finish(.completed)
        try sourceStore.save(completed)
        let unrelated = try task(workspace: workspace)
        try sourceStore.save(unrelated)
        let destination = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let fork = try XCTUnwrap(VyronDevelopmentTaskFork.prepare(
            workspace: workspace, source: session(owner: owner, task: completed), destination: destination
        ))
        try fork.save()
        let destinationStore = try store(workspace: workspace, owner: destination.conversationID)
        let copied = try XCTUnwrap(destinationStore.load(id: destination.responseID))
        XCTAssertEqual(copied.status, .completed)
        XCTAssertEqual(copied.plan, completed.plan)
        XCTAssertEqual(copied.progress.files, completed.progress.files)
        XCTAssertEqual(copied.progress.integrations, completed.progress.integrations)
        let copiedURL = checkpoint(workspace, owner: destination.conversationID, id: destination.responseID)
        let copiedData = try Data(contentsOf: copiedURL)
        let originalURL = checkpoint(workspace, owner: owner, id: completed.identity.id)
        let originalData = try Data(contentsOf: originalURL)
        let nextResponseID = UUID()
        XCTAssertThrowsError(try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: destination.conversationID,
                responseID: nextResponseID,
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: completed.identity.originalGoal, priorResponseIDs: [destination.responseID]
                )
            ),
            goal: "Continue"
        ))
        XCTAssertEqual(try Data(contentsOf: copiedURL), copiedData)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
        XCTAssertNil(try destinationStore.load(id: nextResponseID))
        XCTAssertNil(try destinationStore.load(id: unrelated.identity.id))
        let missing = VyronDevelopmentSessionContext(
            conversationID: UUID(),
            responseID: completed.identity.id,
            continuation: session(owner: owner, task: completed).continuation
        )
        XCTAssertNil(try VyronDevelopmentTaskFork.prepare(
            workspace: workspace,
            source: missing,
            destination: VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        ))
    }

    func testConflictingOrCorruptSourceAndExistingDestinationFailWithoutOverwriting() throws {
        let workspace = try workspace()
        let owner = UUID()
        let original = try task(workspace: workspace)
        let sourceStore = try store(workspace: workspace, owner: owner)
        try sourceStore.save(original)
        var different = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: UUID(), projectPath: workspace.rootURL.path, originalGoal: "A different task."
        ))
        different.finish(.failed)
        try sourceStore.save(different)
        let conflicting = VyronDevelopmentSessionContext(
            conversationID: owner,
            responseID: original.identity.id,
            continuation: VyronDevelopmentContinuationContext(
                originalGoal: original.identity.originalGoal,
                priorResponseIDs: [original.identity.id, different.identity.id]
            )
        )
        let destination = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        XCTAssertThrowsError(try VyronDevelopmentTaskFork.prepare(
            workspace: workspace, source: conflicting, destination: destination
        ))

        let destinationStore = try store(workspace: workspace, owner: destination.conversationID)
        let prior = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: destination.responseID, projectPath: workspace.rootURL.path, originalGoal: "Preserve the destination."
        ))
        try destinationStore.save(prior)
        XCTAssertThrowsError(try VyronDevelopmentTaskFork.prepare(
            workspace: workspace, source: session(owner: owner, task: original), destination: destination
        ))
        XCTAssertEqual(try destinationStore.load(id: destination.responseID), prior)
        try Data("corrupt fixture".utf8).write(to: checkpoint(workspace, owner: owner, id: original.identity.id))
        XCTAssertThrowsError(try VyronDevelopmentTaskFork.prepare(
            workspace: workspace,
            source: session(owner: owner, task: original),
            destination: VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        ))
        XCTAssertEqual(
            try String(contentsOf: checkpoint(workspace, owner: owner, id: original.identity.id)), "corrupt fixture"
        )
    }

    func testRollbackRemovesOnlyExactCreatedCheckpointAndPreservesLaterChanges() throws {
        let workspace = try workspace()
        let owner = UUID()
        let original = try task(workspace: workspace)
        try store(workspace: workspace, owner: owner).save(original)
        let destination = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let fork = try XCTUnwrap(VyronDevelopmentTaskFork.prepare(
            workspace: workspace, source: session(owner: owner, task: original), destination: destination
        ))
        try fork.save()
        try fork.removeCreatedCheckpoint()
        XCTAssertNil(try store(workspace: workspace, owner: destination.conversationID).load(
            id: destination.responseID
        ))
        XCTAssertEqual(try store(workspace: workspace, owner: owner).load(id: original.identity.id), original)
        try fork.save()
        let destinationStore = try store(workspace: workspace, owner: destination.conversationID)
        var changed = try XCTUnwrap(destinationStore.load(id: destination.responseID))
        try changed.recordGuidance("A later explicit user instruction.")
        try destinationStore.save(changed)
        XCTAssertThrowsError(try fork.removeCreatedCheckpoint())
        XCTAssertEqual(try destinationStore.load(id: destination.responseID), changed)
    }

    func testCancelledForkDoesNotCreateCheckpoint() async throws {
        let workspace = try workspace()
        let owner = UUID()
        let original = try task(workspace: workspace)
        try store(workspace: workspace, owner: owner).save(original)
        let destination = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let source = session(owner: owner, task: original)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try VyronDevelopmentTaskFork.prepare(workspace: workspace, source: source, destination: destination)
        }
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled fork must stop before saving.")
        } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        XCTAssertNil(try store(workspace: workspace, owner: destination.conversationID).load(
            id: destination.responseID
        ))
    }

    private func session(owner: UUID, task: VyronDevelopmentTaskState) -> VyronDevelopmentSessionContext {
        VyronDevelopmentSessionContext(
            conversationID: owner,
            responseID: task.identity.id,
            continuation: VyronDevelopmentContinuationContext(
                originalGoal: task.identity.originalGoal, priorResponseIDs: [task.identity.id], guidance: task.guidance
            )
        )
    }

    private func task(workspace: DevelopmentWorkspace) throws -> VyronDevelopmentTaskState {
        var task = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: UUID(), projectPath: workspace.rootURL.path, originalGoal: "Build and validate the template app."
        ))
        try task.updatePlan(VyronDevelopmentPlanUpdate(steps: [
            VyronDevelopmentPlanStep(title: "Create the project", status: .completed),
            VyronDevelopmentPlanStep(title: "Validate the app", status: .pending)
        ]))
        try task.recordFile(VyronDevelopmentFileProgress(
            path: "Main.swift", contentHash: VyronDevelopmentFileProgress.hash(content: "struct Main {}")
        ))
        try task.recordCheck(VyronDevelopmentCheckProgress(
            command: "swift test", result: VyronDevelopmentCheckResult(exitCode: 0, timedOut: false)
        ))
        try task.recordIntegration(VyronDevelopmentIntegrationProgress(
            identity: VyronDevelopmentIntegrationIdentity(
                toolName: "mcp_fixture_create", argumentsHash: String(repeating: "a", count: 64)
            ), status: .started, summary: "The fixture creation may have completed; verify before replay."
        ))
        try task.recordGuidance("Keep the original lifecycle.")
        task.finish(.failed)
        return task
    }

    private func store(workspace: DevelopmentWorkspace, owner: UUID) throws -> VyronDevelopmentTaskStore {
        try VyronDevelopmentTaskStore(
            directoryURL: workspace.taskStateDirectoryURL.appendingPathComponent(owner.uuidString),
            projectPath: workspace.rootURL.path
        )
    }

    private func checkpoint(_ workspace: DevelopmentWorkspace, owner: UUID, id: UUID) -> URL {
        workspace.taskStateDirectoryURL.appendingPathComponent(owner.uuidString)
            .appendingPathComponent(id.uuidString + ".json")
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronTaskFork-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let workspace = try DevelopmentWorkspace(rootURL: directory)
        let projectStorage = workspace.taskStateDirectoryURL.deletingLastPathComponent()
        addTeardownBlock {
            try FileManager.default.removeItem(at: projectStorage)
            try FileManager.default.removeItem(at: directory)
        }
        return workspace
    }
}
