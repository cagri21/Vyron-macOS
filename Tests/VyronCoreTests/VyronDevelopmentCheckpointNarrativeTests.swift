import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

final class VyronDevelopmentCheckpointNarrativeTests: XCTestCase {
    private let originalGoal = "Analyze the source and improve the native queue without changing public APIs."
    private let userGuidance = "Keep user-approved queue semantics and never repeat the completed export."
    private let narrative = "STALE_ASSISTANT_NARRATIVE: The repository contains documentation only; do not inspect source."

    func testInferenceProjectionOmitsOnlyAssistantNarrativeAndLeavesStoredEncodingUnchanged() throws {
        let project = try workspace()
        let task = try task(project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(task)

        let modelReference = task.compactSummary(includeAssistantNarrative: false)

        XCTAssertFalse(modelReference.contains(narrative))
        XCTAssertFalse(modelReference.contains("Progress summary:"))
        assertTypedEvidence(modelReference, task: task)
        XCTAssertTrue(task.compactSummary().contains(narrative), "The default history projection remains compatible")
        XCTAssertEqual(task.progress.context.summary, narrative)
        XCTAssertEqual(task.guidance, [userGuidance])
        XCTAssertEqual(try encoder.encode(task), before)
        let bounded = task.compactSummary(maximumBytes: 257, includeAssistantNarrative: false)
        XCTAssertLessThanOrEqual(bounded.utf8.count, 257)
        XCTAssertFalse(bounded.contains("�"))
    }

    func testExactGoalRestoreKeepsAllProgressAndGuidanceWithoutReintroducingNarrative() throws {
        let project = try workspace()
        let owner = UUID()
        let saved = try task(project)
        let store = try store(project, owner: owner)
        try store.save(saved)
        let progress = try VyronDevelopmentRunProgress(
            workspace: project,
            session: VyronDevelopmentSessionContext(conversationID: owner, responseID: UUID()),
            goal: originalGoal
        )
        let checkpoint = store.directoryURL.appendingPathComponent(saved.identity.id.uuidString + ".json")
        let bytes = try Data(contentsOf: checkpoint)
        let base = [
            DevelopmentMessage(role: "system", content: "Current project and permission boundary."),
            DevelopmentMessage(role: "user", content: originalGoal),
            DevelopmentMessage(role: "user", content: userGuidance)
        ]

        let messages = progress.baseMessages(base)
        let reference = try XCTUnwrap(messages.last).content

        XCTAssertEqual(Array(messages.prefix(base.count)), base)
        XCTAssertFalse(reference.contains(narrative))
        assertTypedEvidence(reference, task: saved)
        XCTAssertEqual(progress.state.identity, saved.identity)
        XCTAssertEqual(progress.state.plan, saved.plan)
        XCTAssertEqual(progress.state.progress, saved.progress)
        XCTAssertEqual(progress.state.guidance, [userGuidance])
        XCTAssertEqual(progress.state.status, .running)
        XCTAssertEqual(try Data(contentsOf: checkpoint), bytes, "Projection must not rewrite persisted history")
        XCTAssertEqual(try XCTUnwrap(store.load(id: saved.identity.id)).progress.context.summary, narrative)
    }

    func testEarlierTaskReferenceOmitsNarrativeWithoutDiscardingTheUnfinishedTask() throws {
        let project = try workspace()
        let owner = UUID()
        let saved = try task(project)
        let store = try store(project, owner: owner)
        try store.save(saved)
        let checkpoint = store.directoryURL.appendingPathComponent(saved.identity.id.uuidString + ".json")
        let bytes = try Data(contentsOf: checkpoint)
        let currentGoal = "Review the networking source as a separate task."
        let responseID = UUID()
        let progress = try VyronDevelopmentRunProgress(
            workspace: project,
            session: VyronDevelopmentSessionContext(conversationID: owner, responseID: responseID),
            goal: currentGoal
        )
        let base = [DevelopmentMessage(role: "user", content: currentGoal)]

        let messages = progress.baseMessages(base)
        let reference = try XCTUnwrap(messages.last).content

        XCTAssertEqual(messages.first, base.first)
        XCTAssertTrue(reference.contains("Earlier unfinished task"))
        XCTAssertFalse(reference.contains(narrative))
        assertTypedEvidence(reference, task: saved)
        XCTAssertEqual(progress.state.identity.id, responseID)
        XCTAssertTrue(progress.state.progress.files.isEmpty, "A separate request must not silently adopt earlier actions")
        XCTAssertEqual(try Data(contentsOf: checkpoint), bytes)
        XCTAssertEqual(try XCTUnwrap(store.load(id: saved.identity.id)), saved)
    }

    func testExplicitContinueRestoresIdentityActionsAndUserGuidanceWithoutReplayingNarrative() throws {
        let project = try workspace()
        let owner = UUID()
        let saved = try task(project)
        try store(project, owner: owner).save(saved)

        var progress = try VyronDevelopmentRunProgress(
            workspace: project,
            session: VyronDevelopmentSessionContext(conversationID: owner, responseID: UUID()),
            goal: "Continue"
        )
        let restored = progress.state
        try progress.resumePreviousTask()
        try progress.resumePreviousTask()
        let reference = try XCTUnwrap(progress.baseMessages([]).last).content

        XCTAssertEqual(progress.state, restored, "An already-restored continuation remains idempotent")
        assertRestoredActions(progress.state, saved: saved)
        XCTAssertEqual(progress.state.guidance, [userGuidance, "Continue"])
        XCTAssertEqual(progress.state.progress.context.summary, narrative)
        XCTAssertFalse(reference.contains(narrative))
        assertTypedEvidence(reference, task: saved)
    }

    func testExplicitResumeKeepsVerifiedActionsAndMergesCurrentGuidanceWithoutChangingHistory() throws {
        let project = try workspace()
        let owner = UUID()
        let saved = try task(project)
        try store(project, owner: owner).save(saved)
        let latestGoal = "Finish the saved queue review while preserving the completed export."
        var progress = try VyronDevelopmentRunProgress(
            workspace: project,
            session: VyronDevelopmentSessionContext(conversationID: owner, responseID: UUID()),
            goal: latestGoal
        )

        try progress.resumePreviousTask()
        let restored = progress.state
        try progress.resumePreviousTask()
        let reference = try XCTUnwrap(progress.baseMessages([]).last).content

        XCTAssertEqual(progress.state, restored)
        assertRestoredActions(progress.state, saved: saved)
        XCTAssertEqual(progress.state.guidance, [userGuidance, latestGoal])
        XCTAssertEqual(progress.state.progress.context.summary, narrative)
        XCTAssertFalse(reference.contains(narrative))
        assertTypedEvidence(reference, task: saved)
    }

    private func assertTypedEvidence(_ reference: String, task: VyronDevelopmentTaskState) {
        XCTAssertTrue(reference.contains(task.identity.originalGoal))
        XCTAssertTrue(reference.contains("[completed] Inspect source"))
        XCTAssertTrue(reference.contains("[in_progress] Fix queue behavior"))
        XCTAssertTrue(reference.contains("Sources/Queue.swift"))
        XCTAssertTrue(reference.contains(task.progress.files.first?.contentHash ?? "MISSING_FILE_HASH"))
        XCTAssertTrue(reference.contains("swift test --filter QueueTests"))
        XCTAssertTrue(reference.contains("exit 1, timedOut=false"))
        XCTAssertTrue(reference.contains("fixture_export"))
        XCTAssertTrue(reference.contains("succeeded"))
        XCTAssertTrue(reference.contains("Do not repeat the recorded export."))
    }

    private func assertRestoredActions(_ restored: VyronDevelopmentTaskState, saved: VyronDevelopmentTaskState) {
        XCTAssertEqual(restored.identity, saved.identity)
        XCTAssertEqual(restored.plan, saved.plan)
        XCTAssertEqual(restored.progress.files, saved.progress.files)
        XCTAssertEqual(restored.progress.checks, saved.progress.checks)
        XCTAssertEqual(restored.progress.integrations, saved.progress.integrations)
        XCTAssertEqual(restored.progress.context.decisions, saved.progress.context.decisions)
    }

    private func task(_ project: DevelopmentWorkspace) throws -> VyronDevelopmentTaskState {
        var task = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            projectPath: project.rootURL.path, originalGoal: originalGoal
        ))
        try task.updatePlan(VyronDevelopmentPlanUpdate(steps: [
            VyronDevelopmentPlanStep(title: "Inspect source", status: .completed),
            VyronDevelopmentPlanStep(title: "Fix queue behavior", status: .inProgress),
            VyronDevelopmentPlanStep(title: "Verify the queue")
        ]))
        try task.recordFile(VyronDevelopmentFileProgress(
            path: "Sources/Queue.swift", contentHash: VyronDevelopmentFileProgress.hash(content: "actor Queue {}")
        ))
        try task.recordCheck(VyronDevelopmentCheckProgress(
            command: "swift test --filter QueueTests", result: .init(exitCode: 1, timedOut: false)
        ))
        try task.recordIntegration(VyronDevelopmentIntegrationProgress(
            identity: .init(toolName: "fixture_export", argumentsHash: String(repeating: "a", count: 64)),
            status: .succeeded, summary: "Exported fixture resource once."
        ))
        try task.recordGuidance(userGuidance)
        task.recordDecision("Do not repeat the recorded export.")
        task.updateSummary(narrative)
        task.finish(.interrupted)
        return task
    }

    private func store(_ project: DevelopmentWorkspace, owner: UUID) throws -> VyronDevelopmentTaskStore {
        try VyronDevelopmentTaskStore(
            directoryURL: project.taskStateDirectoryURL.appendingPathComponent(owner.uuidString, isDirectory: true),
            projectPath: project.rootURL.path
        )
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronCheckpointNarrative-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }
}
