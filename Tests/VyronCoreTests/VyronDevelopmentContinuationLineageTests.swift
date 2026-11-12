import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentContinuationLineageTests: XCTestCase {
    func testVerifiedLegacyChainCombinesEarlierPlanWithLatestFileAndUncertainActionEvidence() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        var earlier = checkpoint(goal: "continıe", workspace: workspace)
        try earlier.updatePlan(VyronDevelopmentPlanUpdate(steps: plan))
        try earlier.recordGuidance("Keep the existing storyboard lifecycle.")
        try earlier.recordCheck(VyronDevelopmentCheckProgress(
            command: "swift test", result: VyronDevelopmentCheckResult(exitCode: 0, timedOut: false)
        ))
        try earlier.recordIntegration(integration(hash: "a", status: .succeeded, time: 1_000))
        earlier.finish(.failed)
        try store.save(earlier)
        var later = checkpoint(goal: "continue", workspace: workspace)
        let file = VyronDevelopmentFileProgress(
            path: "iOSAppTemplate/ViewController.swift",
            contentHash: VyronDevelopmentFileProgress.hash(content: "final class ViewController {}"),
            recordedAt: Date(timeIntervalSince1970: 2_000)
        )
        try later.recordFile(file)
        try later.recordIntegration(integration(hash: "b", status: .started, time: 2_000))
        later.finish(.failed)
        try store.save(later)
        let originalGoal = "create a ios template app"

        var progress = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: owner, responseID: UUID(),
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: originalGoal, priorResponseIDs: [earlier.identity.id, later.identity.id],
                    guidance: ["Keep the existing storyboard lifecycle.", "Support dark mode."]
                )
            ),
            goal: "Continue"
        )

        XCTAssertEqual(progress.state.identity.id, later.identity.id)
        XCTAssertEqual(progress.state.identity.originalGoal, originalGoal)
        XCTAssertEqual(progress.state.plan, earlier.plan)
        XCTAssertEqual(progress.state.progress.files, [file])
        XCTAssertEqual(progress.state.progress.checks, earlier.progress.checks)
        XCTAssertEqual(progress.state.progress.integrations.count, 2)
        XCTAssertEqual(progress.state.progress.integrations.last?.status, .started)
        XCTAssertEqual(progress.state.guidance, [
            "Keep the existing storyboard lifecycle.", "Support dark mode.", "Continue"
        ])
        XCTAssertNoThrow(try progress.resumePreviousTask())
        XCTAssertEqual(try store.load(id: later.identity.id)?.identity.originalGoal, originalGoal)
        XCTAssertEqual(try store.load(id: earlier.identity.id)?.identity.originalGoal, "continıe")
    }

    func testVerifiedSubstantiveOriginalKeepsIdentityAndLatestEvidenceWithoutReadingUnlinkedRecords() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        let goal = "Implement the complete iOS template app."
        var original = checkpoint(goal: goal, workspace: workspace)
        try original.updatePlan(VyronDevelopmentPlanUpdate(steps: plan))
        try original.recordFile(VyronDevelopmentFileProgress(
            path: "ViewController.swift", contentHash: VyronDevelopmentFileProgress.hash(content: "Old"),
            recordedAt: Date(timeIntervalSince1970: 1_000)
        ))
        try original.recordIntegration(integration(hash: "a", status: .started, time: 1_000))
        original.finish(.failed)
        try store.save(original)
        var continuation = checkpoint(goal: "continue", workspace: workspace)
        let latest = VyronDevelopmentFileProgress(
            path: "ViewController.swift", contentHash: VyronDevelopmentFileProgress.hash(content: "Latest"),
            recordedAt: Date(timeIntervalSince1970: 2_000)
        )
        try continuation.recordFile(latest)
        try continuation.recordIntegration(integration(hash: "a", status: .succeeded, time: 2_000))
        continuation.finish(.failed)
        try store.save(continuation)
        let unrelated = store.directoryURL.appendingPathComponent(UUID().uuidString + ".json")
        let unrelatedData = Data("{unlinked corrupt record".utf8)
        try unrelatedData.write(to: unrelated)

        let progress = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: owner, responseID: UUID(),
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: goal, priorResponseIDs: [original.identity.id, continuation.identity.id]
                )
            ),
            goal: "Continue"
        )

        XCTAssertEqual(progress.state.identity.id, original.identity.id)
        XCTAssertEqual(progress.state.identity.startedAt, original.identity.startedAt)
        XCTAssertEqual(progress.state.progress.files, [latest])
        XCTAssertEqual(progress.state.progress.integrations.count, 1)
        XCTAssertEqual(progress.state.progress.integrations.first?.status, .succeeded)
        XCTAssertEqual(try Data(contentsOf: unrelated), unrelatedData)
    }

    func testAmbiguousUnhintedContinuationRejectsBeforeCreatingOrChangingCheckpoints() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        let first = checkpoint(goal: "Build the iOS template app.", workspace: workspace)
        let second = checkpoint(goal: "Review a separate networking feature.", workspace: workspace)
        try store.save(first)
        try store.save(second)
        let responseID = UUID()
        let before = try FileManager.default.contentsOfDirectory(atPath: store.directoryURL.path).sorted()

        XCTAssertThrowsError(try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(conversationID: owner, responseID: responseID),
            goal: "Continue"
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("more than one unfinished task"))
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directoryURL.path).sorted(), before)
        XCTAssertNil(try store.load(id: responseID))
        XCTAssertEqual(try store.load(id: first.identity.id), first)
        XCTAssertEqual(try store.load(id: second.identity.id), second)
    }

    func testConflictingCompletedPlansInVerifiedChainAreRejectedWithoutReplacingSavedTasks() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        var earlier = checkpoint(goal: "Create the template app.", workspace: workspace)
        try earlier.updatePlan(VyronDevelopmentPlanUpdate(steps: plan))
        earlier.finish(.failed)
        try store.save(earlier)
        var later = checkpoint(goal: "continue", workspace: workspace)
        try later.updatePlan(VyronDevelopmentPlanUpdate(steps: [VyronDevelopmentPlanStep(title: "Different stage")]))
        later.finish(.failed)
        try store.save(later)

        XCTAssertThrowsError(try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: owner, responseID: UUID(),
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: earlier.identity.originalGoal, priorResponseIDs: [earlier.identity.id, later.identity.id]
                )
            ),
            goal: "Continue"
        ))

        XCTAssertEqual(try store.load(id: earlier.identity.id), earlier)
        XCTAssertEqual(try store.load(id: later.identity.id), later)
    }

    func testConflictingActionEvidenceWithoutReliableOrderIsRejectedInsteadOfDiscarded() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        var earlier = checkpoint(goal: "Create a fixture resource.", workspace: workspace)
        try earlier.recordIntegration(integration(hash: "a", status: .succeeded, time: 1_000))
        earlier.finish(.failed)
        try store.save(earlier)
        var later = checkpoint(goal: "continue", workspace: workspace)
        try later.recordIntegration(integration(hash: "a", status: .started, time: 1_000))
        later.finish(.failed)
        try store.save(later)

        XCTAssertThrowsError(try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(
                conversationID: owner, responseID: UUID(),
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: earlier.identity.originalGoal, priorResponseIDs: [earlier.identity.id, later.identity.id]
                )
            ),
            goal: "Continue"
        ))

        XCTAssertEqual(try store.load(id: earlier.identity.id), earlier)
        XCTAssertEqual(try store.load(id: later.identity.id), later)
    }

    func testGenericOnlyHistoryWithoutUserAnchorDoesNotInventAnOriginalGoal() throws {
        let workspace = try workspace()
        let owner = UUID()
        let store = try store(workspace, owner: owner)
        let legacy = checkpoint(goal: "Continue", workspace: workspace)
        try store.save(legacy)

        let progress = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(conversationID: owner, responseID: UUID()),
            goal: "Continue"
        )

        XCTAssertEqual(progress.state.identity.originalGoal, "Continue")
        XCTAssertEqual(progress.state.identity.id, legacy.identity.id)
        XCTAssertTrue(progress.state.plan.isEmpty)
    }

    func testVerifiedUserAnchorCanRecoverMissingCheckpointWithoutBorrowingAnotherProjectEvidence() throws {
        let originalWorkspace = try workspace()
        let currentWorkspace = try workspace()
        let owner = UUID()
        let originalStore = try store(originalWorkspace, owner: owner)
        var foreign = checkpoint(goal: "continue", workspace: originalWorkspace)
        try foreign.updatePlan(VyronDevelopmentPlanUpdate(steps: plan))
        foreign.finish(.failed)
        try originalStore.save(foreign)
        let responseID = UUID()
        let goal = "Build the app in the current project."

        let progress = try VyronDevelopmentRunProgress(
            workspace: currentWorkspace,
            session: VyronDevelopmentSessionContext(
                conversationID: owner, responseID: responseID,
                continuation: VyronDevelopmentContinuationContext(
                    originalGoal: goal, priorResponseIDs: [foreign.identity.id], guidance: ["Inspect before editing."]
                )
            ),
            goal: "Continue"
        )

        XCTAssertEqual(progress.state.identity.id, responseID)
        XCTAssertEqual(progress.state.identity.originalGoal, goal)
        XCTAssertTrue(progress.state.plan.isEmpty)
        XCTAssertTrue(progress.state.progress.files.isEmpty)
        XCTAssertEqual(progress.state.guidance, ["Inspect before editing.", "Continue"])
        XCTAssertEqual(try originalStore.load(id: foreign.identity.id), foreign)
    }

    func testCancellationBeforeContinuationCreatesNoCheckpoint() async throws {
        let workspace = try workspace()
        let owner = UUID()
        let execution = Task {
            try VyronDevelopmentRunProgress(
                workspace: workspace,
                session: VyronDevelopmentSessionContext(conversationID: owner, responseID: UUID()),
                goal: "Continue"
            )
        }
        execution.cancel()

        switch await execution.result {
        case .success:
            XCTFail("A canceled continuation must not create a checkpoint.")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: workspace.taskStateDirectoryURL.appendingPathComponent(owner.uuidString).path
        ))
    }

    private var plan: [VyronDevelopmentPlanStep] {
        [
            VyronDevelopmentPlanStep(title: "Create project files", status: .completed),
            VyronDevelopmentPlanStep(title: "Build main screen", status: .inProgress),
            VyronDevelopmentPlanStep(title: "Validate app", status: .pending)
        ]
    }

    private func integration(
        hash: String, status: VyronDevelopmentIntegrationStatus, time: TimeInterval
    ) -> VyronDevelopmentIntegrationProgress {
        VyronDevelopmentIntegrationProgress(
            identity: VyronDevelopmentIntegrationIdentity(
                toolName: "mcp_fixture_create", argumentsHash: String(repeating: hash, count: 64)
            ),
            status: status, summary: "Recorded fixture action.", recordedAt: Date(timeIntervalSince1970: time)
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
            .appendingPathComponent("VyronContinuationLineage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }
}
