import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentContinuationLifecycleTests: XCTestCase {
    func testCompletedLatestTaskCannotBeRevivedByAnOlderFailedGenericCheckpoint() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        var original = checkpoint(goal: "Create the iOS template app.", workspace: workspace)
        try store.save(original)
        let legacy = checkpoint(goal: "continue", workspace: workspace)
        try store.save(legacy)
        // The first task identity was reused and completed after the later continuation response.
        original.finish(.completed)
        try store.save(original)
        XCTAssertGreaterThan(original.lifecycle.updatedAt, legacy.lifecycle.updatedAt)
        let responseID = UUID()

        XCTAssertThrowsError(try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: owner, responseID: responseID,
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: original.identity.originalGoal, priorResponseIDs: [original.identity.id, legacy.identity.id]
                )
            ),
            goal: "Continue"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("already complete"))
        }

        XCTAssertEqual(try store.load(id: original.identity.id), original)
        XCTAssertEqual(try store.load(id: legacy.identity.id), legacy)
        XCTAssertNil(try store.load(id: responseID))
    }

    func testNewerFailedContinuationCanResumeAfterAnOlderCompletedTask() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        var original = checkpoint(goal: "Create the iOS template app.", workspace: workspace)
        try original.updatePlan(VyronDevelopmentPlanUpdate(steps: [
            VyronDevelopmentPlanStep(title: "Create project files", status: .completed)
        ]))
        original.finish(.completed)
        try store.save(original)
        var newer = checkpoint(goal: "continue", workspace: workspace)
        let file = VyronDevelopmentFileProgress(
            path: "ViewController.swift", contentHash: VyronDevelopmentFileProgress.hash(content: "Latest change")
        )
        try newer.recordFile(file)
        newer.finish(.failed)
        try store.save(newer)
        XCTAssertGreaterThan(newer.lifecycle.updatedAt, original.lifecycle.updatedAt)

        let progress = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: owner, responseID: UUID(),
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: original.identity.originalGoal, priorResponseIDs: [original.identity.id, newer.identity.id]
                )
            ),
            goal: "Continue"
        )

        XCTAssertEqual(progress.state.identity.id, original.identity.id)
        XCTAssertEqual(progress.state.status, .running)
        XCTAssertEqual(progress.state.plan, original.plan)
        XCTAssertEqual(progress.state.progress.files, [file])
        XCTAssertEqual(progress.state.identity.originalGoal, original.identity.originalGoal)
    }

    private func checkpoint(goal: String, workspace: DevelopmentWorkspace) -> VyronDevelopmentTaskState {
        var state = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: UUID(), projectPath: workspace.rootURL.path, originalGoal: goal
        ))
        state.finish(.failed)
        return state
    }

    private func store(_ workspace: DevelopmentWorkspace, owner: UUID) throws -> VyronDevelopmentTaskStore {
        try VyronDevelopmentTaskStore(
            directoryURL: workspace.taskStateDirectoryURL.appendingPathComponent(owner.uuidString),
            projectPath: workspace.rootURL.path
        )
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronContinuationLifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }
}
