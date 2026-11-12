import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentContinuationOrderingTests: XCTestCase {
    func testVerifiedRepeatedGuidancePreservesTheFinalAuthoritativeChoice() throws {
        let workspace = try workspace()
        let guidance = ["Use blue", "Use red", "Use blue"]

        let progress = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: UUID(), responseID: UUID(),
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: "Build the app screen.", priorResponseIDs: [], guidance: guidance
                )
            ),
            goal: "Continue"
        )

        XCTAssertEqual(progress.state.guidance, guidance + ["Continue"])
    }

    func testVerifiedGuidanceExtendsTheStoredOrderedPrefixAcrossContinueControls() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        var saved = checkpoint(goal: "Build the app screen.", workspace: workspace)
        for guidance in ["Use blue", "Continue", "Use red", "Continue"] {
            try saved.recordGuidance(guidance)
        }
        saved.finish(.failed)
        try store.save(saved)

        let progress = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: owner, responseID: UUID(),
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: saved.identity.originalGoal, priorResponseIDs: [saved.identity.id],
                    guidance: ["Use blue", "Use red", "Use blue"]
                )
            ),
            goal: "Continue"
        )

        XCTAssertEqual(progress.state.guidance.filter {
            !VyronDevelopmentContinuationContext.isContinuationRequest($0)
        }, ["Use blue", "Use red", "Use blue"])
        XCTAssertEqual(progress.state.guidance.last, "Continue")
    }

    func testNewerReusedOriginalCheckpointIsNotDowngradedByStaleLaterResponseIdentity() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        var original = checkpoint(goal: "Build the complete template app.", workspace: workspace)
        let oldPlan = [
            VyronDevelopmentPlanStep(title: "A", status: .completed),
            VyronDevelopmentPlanStep(title: "B", status: .inProgress),
            VyronDevelopmentPlanStep(title: "C", status: .pending)
        ]
        try original.updatePlan(VyronDevelopmentPlanUpdate(steps: oldPlan))
        try store.save(original)
        var stale = checkpoint(goal: "continue", workspace: workspace)
        try stale.updatePlan(VyronDevelopmentPlanUpdate(steps: oldPlan))
        let uncertain = VyronDevelopmentIntegrationProgress(
            identity: VyronDevelopmentIntegrationIdentity(
                toolName: "mcp_fixture_create", argumentsHash: String(repeating: "a", count: 64)
            ),
            status: .started, summary: "An earlier action needs outcome inspection."
        )
        try stale.recordIntegration(uncertain)
        stale.finish(.failed)
        try store.save(stale)
        let currentPlan = [
            VyronDevelopmentPlanStep(title: "A", status: .completed),
            VyronDevelopmentPlanStep(title: "B", status: .completed),
            VyronDevelopmentPlanStep(title: "C", status: .inProgress)
        ]
        try original.updatePlan(VyronDevelopmentPlanUpdate(steps: currentPlan))
        try original.recordGuidance("Keep the completed A and B stages.")
        original.finish(.failed)
        try store.save(original)
        XCTAssertGreaterThan(original.lifecycle.updatedAt, stale.lifecycle.updatedAt)

        let progress = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: owner, responseID: UUID(),
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: original.identity.originalGoal, priorResponseIDs: [original.identity.id, stale.identity.id]
                )
            ),
            goal: "Continue"
        )

        XCTAssertEqual(progress.state.identity.id, original.identity.id)
        XCTAssertEqual(progress.state.plan, currentPlan)
        XCTAssertEqual(progress.state.progress.integrations, [uncertain])
        XCTAssertTrue(progress.state.guidance.contains("Keep the completed A and B stages."))
    }

    func testConflictingEqualTimeSnapshotsCannotChooseStatusPlanOrGuidanceByResponseOrder() throws {
        for conflict in ["status", "plan", "guidance"] {
            let workspace = try workspace()
            let owner = UUID()
            let store = try store(workspace, owner: owner)
            var original = checkpoint(goal: "Build the app screen.", workspace: workspace)
            let plan = [VyronDevelopmentPlanStep(title: "A", status: .inProgress)]
            try original.updatePlan(VyronDevelopmentPlanUpdate(steps: plan))
            var other = checkpoint(goal: "continue", workspace: workspace)
            try other.updatePlan(VyronDevelopmentPlanUpdate(steps: plan))
            switch conflict {
            case "status": other.finish(.completed)
            case "plan":
                try other.updatePlan(VyronDevelopmentPlanUpdate(steps: [VyronDevelopmentPlanStep(title: "B")]))
            default:
                try original.recordGuidance("Use blue")
                try other.recordGuidance("Use red")
            }
            let timestamp = Date().addingTimeInterval(1_000)
            original = try withLifecycleDate(original, date: timestamp)
            other = try withLifecycleDate(other, date: timestamp)
            for ids in [[original.identity.id, other.identity.id], [other.identity.id, original.identity.id]] {
                try store.save(original)
                try store.save(other)
                XCTAssertThrowsError(try VyronDevelopmentRunProgress(
                    workspace: workspace,
                    session: VyronDevelopmentSessionContext(
                        conversationID: owner, responseID: UUID(),
                        continuation: VyronDevelopmentContinuationContext(
                            originalGoal: original.identity.originalGoal, priorResponseIDs: ids
                        )
                    ),
                    goal: "Continue"
                ), "Conflicting \(conflict) snapshots require an explicit resolution.")
                XCTAssertEqual(try store.load(id: original.identity.id), original)
                XCTAssertEqual(try store.load(id: other.identity.id), other)
            }
        }
    }

    private func withLifecycleDate(
        _ state: VyronDevelopmentTaskState, date: Date
    ) throws -> VyronDevelopmentTaskState {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var lifecycle = try XCTUnwrap(object["lifecycle"] as? [String: Any])
        lifecycle["updatedAt"] = date.timeIntervalSinceReferenceDate
        object["lifecycle"] = lifecycle
        return try JSONDecoder().decode(
            VyronDevelopmentTaskState.self, from: JSONSerialization.data(withJSONObject: object)
        )
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
            .appendingPathComponent("VyronContinuationOrdering-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }
}
