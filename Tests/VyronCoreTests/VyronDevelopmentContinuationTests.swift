import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentContinuationTests: XCTestCase {
    func testGenericContinueRestoresTheOriginalUnfinishedTaskAndAllItsEvidence() throws {
        let workspace = try workspace()
        let conversationID = UUID()
        let original = try savedTask(
            goal: "Create an iOS template app with a storyboard and a view controller.",
            workspace: workspace, conversationID: conversationID
        )
        let responseID = UUID()

        let continuation = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(conversationID: conversationID, responseID: responseID),
            goal: "Continue"
        )

        XCTAssertEqual(continuation.state.identity.id, original.identity.id)
        XCTAssertNotEqual(continuation.state.identity.id, responseID)
        XCTAssertEqual(continuation.state.identity.originalGoal, original.identity.originalGoal)
        XCTAssertEqual(continuation.state.plan, original.plan)
        XCTAssertEqual(continuation.state.progress.files, original.progress.files)
        XCTAssertEqual(continuation.state.progress.checks, original.progress.checks)
        XCTAssertEqual(continuation.state.progress.integrations, original.progress.integrations)
        XCTAssertEqual(continuation.state.guidance, original.guidance + ["Continue"])
        XCTAssertEqual(continuation.state.status, .running)
    }

    func testFailedGenericContinueCheckpointCannotShadowTheSubstantiveOriginalTask() throws {
        let workspace = try workspace()
        let conversationID = UUID()
        let original = try savedTask(
            goal: "Build the iOS template app and validate its existing project.",
            workspace: workspace, conversationID: conversationID
        )
        let legacy = try savedTask(goal: "continue", workspace: workspace, conversationID: conversationID)

        let continuation = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(conversationID: conversationID, responseID: UUID()),
            goal: "continue"
        )

        XCTAssertEqual(continuation.state.identity.id, original.identity.id)
        XCTAssertNotEqual(continuation.state.identity.id, legacy.identity.id)
        XCTAssertEqual(continuation.state.identity.originalGoal, original.identity.originalGoal)
        XCTAssertEqual(continuation.state.plan, original.plan)
    }

    func testModelResumeToolIsIdempotentAfterImplicitContinuation() throws {
        let workspace = try workspace()
        let conversationID = UUID()
        let original = try savedTask(
            goal: "Finish the template app's three planned stages.",
            workspace: workspace, conversationID: conversationID
        )
        var continuation = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(conversationID: conversationID, responseID: UUID()),
            goal: "Continue"
        )
        let guidance = continuation.state.guidance

        XCTAssertNoThrow(try continuation.resumePreviousTask())
        XCTAssertNoThrow(try continuation.resumePreviousTask())

        XCTAssertEqual(continuation.state.identity.id, original.identity.id)
        XCTAssertEqual(continuation.state.plan, original.plan)
        XCTAssertEqual(continuation.state.guidance, guidance)
    }

    func testNewSubstantiveGoalDoesNotImplicitlyResumeAnEarlierTask() throws {
        let workspace = try workspace()
        let conversationID = UUID()
        let original = try savedTask(
            goal: "Build the iOS template app.", workspace: workspace, conversationID: conversationID
        )
        let responseID = UUID()
        let goal = "Review the networking layer for a separate feature."

        let newTask = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(conversationID: conversationID, responseID: responseID),
            goal: goal
        )

        XCTAssertEqual(newTask.state.identity.id, responseID)
        XCTAssertNotEqual(newTask.state.identity.id, original.identity.id)
        XCTAssertEqual(newTask.state.identity.originalGoal, goal)
        XCTAssertTrue(newTask.state.plan.isEmpty)
        XCTAssertTrue(newTask.state.progress.files.isEmpty)
        XCTAssertTrue(newTask.state.progress.integrations.isEmpty)
    }

    func testContinuationCannotAdoptAnotherConversationsTask() throws {
        let workspace = try workspace()
        let foreign = try savedTask(
            goal: "Build a different app.", workspace: workspace, conversationID: UUID()
        )
        let responseID = UUID()

        let continuation = try VyronDevelopmentRunProgress(
            workspace: workspace,
            session: VyronDevelopmentSessionContext(conversationID: UUID(), responseID: responseID),
            goal: "Continue"
        )

        XCTAssertEqual(continuation.state.identity.id, responseID)
        XCTAssertNotEqual(continuation.state.identity.id, foreign.identity.id)
        XCTAssertEqual(continuation.state.identity.originalGoal, "Continue")
        XCTAssertTrue(continuation.state.progress.files.isEmpty)
    }

    private func savedTask(
        goal: String, workspace: DevelopmentWorkspace, conversationID: UUID
    ) throws -> VyronDevelopmentTaskState {
        var task = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: UUID(), projectPath: workspace.rootURL.path, originalGoal: goal
        ))
        try task.updatePlan(VyronDevelopmentPlanUpdate(steps: [
            VyronDevelopmentPlanStep(title: "Create the project files", status: .completed),
            VyronDevelopmentPlanStep(title: "Build the main screen", status: .inProgress),
            VyronDevelopmentPlanStep(title: "Validate the app", status: .pending)
        ]))
        try task.recordFile(VyronDevelopmentFileProgress(
            path: "iOSAppTemplate/ViewController.swift",
            contentHash: VyronDevelopmentFileProgress.hash(content: "final class ViewController {}")
        ))
        try task.recordCheck(VyronDevelopmentCheckProgress(
            command: "swift test", result: VyronDevelopmentCheckResult(exitCode: 0, timedOut: false),
            summary: "A saved local test result."
        ))
        try task.recordIntegration(VyronDevelopmentIntegrationProgress(
            identity: VyronDevelopmentIntegrationIdentity(
                toolName: "mcp_fixture_create", argumentsHash: String(repeating: "a", count: 64)
            ),
            status: .succeeded, summary: "Created fixture resource exact-resource-42."
        ))
        try task.recordGuidance("Keep the existing storyboard lifecycle.")
        task.finish(.failed, detail: "Fixture interrupted before the final stage.")
        let store = try VyronDevelopmentTaskStore(
            directoryURL: workspace.taskStateDirectoryURL.appendingPathComponent(conversationID.uuidString),
            projectPath: workspace.rootURL.path
        )
        try store.save(task)
        return task
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronContinuation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }
}
