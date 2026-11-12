import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentContinuationEffortTests: XCTestCase {
    func testAutomaticContinueUsesRestoredComplexGoalForSelectionAndInference() async throws {
        let project = try workspace()
        let conversationID = UUID()
        let goal = "Analyze and refactor the existing storage architecture."
        let originalID = try savedTask(goal: goal, in: project, conversationID: conversationID)
        let provider = VyronContinuationEffortTestProvider()
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: conversationID,
            responseID: UUID(),
            continuation: VyronDevelopmentContinuationContext(originalGoal: goal, priorResponseIDs: [originalID])
        ))

        let result = try await agent.run(
            goal: "Continue", model: "preferred-coder", automaticModelSelection: true, effort: .automatic,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let selections = await provider.recordedModelRequests()
        let steps = await provider.recordedStepEfforts()
        XCTAssertEqual(selections, [VyronContinuationModelSelection(
            model: "preferred-coder", automaticModelSelection: true, effort: .deep
        )])
        XCTAssertEqual(steps, [.deep])
        XCTAssertEqual(result.model, "fixture-deep")
    }

    func testExplicitQuickAndManualModelRemainUnchangedWhenContinuingAComplexGoal() async throws {
        let project = try workspace()
        let conversationID = UUID()
        let goal = "Analyze and refactor the existing storage architecture."
        let originalID = try savedTask(goal: goal, in: project, conversationID: conversationID)
        let provider = VyronContinuationEffortTestProvider()
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: conversationID,
            responseID: UUID(),
            continuation: VyronDevelopmentContinuationContext(originalGoal: goal, priorResponseIDs: [originalID])
        ))

        let result = try await agent.run(
            goal: "Continue", model: "manual-coder", automaticModelSelection: false, effort: .quick,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let selections = await provider.recordedModelRequests()
        let steps = await provider.recordedStepEfforts()
        XCTAssertEqual(selections, [VyronContinuationModelSelection(
            model: "manual-coder", automaticModelSelection: false, effort: .quick
        )])
        XCTAssertEqual(steps, [.quick])
        XCTAssertEqual(result.model, "manual-coder")
    }

    func testAutomaticContinueIncludesSubstantiveSavedGuidanceInItsEffort() async throws {
        let project = try workspace()
        let conversationID = UUID()
        let goal = "Open the existing project."
        let originalID = try savedTask(
            goal: goal, in: project, conversationID: conversationID,
            guidance: ["Analyze and refactor its persistence boundaries before changing code."]
        )
        let provider = VyronContinuationEffortTestProvider()
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: conversationID,
            responseID: UUID(),
            continuation: VyronDevelopmentContinuationContext(originalGoal: goal, priorResponseIDs: [originalID])
        ))

        _ = try await agent.run(
            goal: "Continue", model: "preferred-coder", effort: .automatic,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let selections = await provider.recordedModelRequests()
        let steps = await provider.recordedStepEfforts()
        XCTAssertEqual(selections.first?.effort, .deep)
        XCTAssertEqual(steps, [.deep])
    }

    func testContinueControlMessagesDoNotChangeASimpleOriginalAutomaticEffort() async throws {
        let project = try workspace()
        let conversationID = UUID()
        let goal = "Open the existing project."
        let originalID = try savedTask(
            goal: goal, in: project, conversationID: conversationID, guidance: ["Continue", "please continue"]
        )
        let provider = VyronContinuationEffortTestProvider()
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: conversationID,
            responseID: UUID(),
            continuation: VyronDevelopmentContinuationContext(originalGoal: goal, priorResponseIDs: [originalID])
        ))

        _ = try await agent.run(
            goal: "Continue", model: "preferred-coder", effort: .automatic,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let selections = await provider.recordedModelRequests()
        let steps = await provider.recordedStepEfforts()
        XCTAssertEqual(selections.first?.effort, .quick)
        XCTAssertEqual(steps, [.quick])
    }

    func testModelSelectionFailureLeavesANewCheckpointFailed() async throws {
        let project = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let provider = VyronContinuationEffortTestProvider(selectionError: .http(503))
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(session)

        do {
            _ = try await agent.run(
                goal: "Analyze the project.", model: "preferred-coder",
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("A model-selection failure must propagate.")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .http(503))
        }

        let saved = try XCTUnwrap(taskStore(in: project, conversationID: session.conversationID).load(id: session.responseID))
        XCTAssertEqual(saved.status, .failed)
        let steps = await provider.recordedStepEfforts()
        XCTAssertTrue(steps.isEmpty)
    }

    func testModelSelectionFailureDoesNotLeaveARestoredCheckpointRunning() async throws {
        let project = try workspace()
        let conversationID = UUID()
        let goal = "Analyze and refactor the existing storage architecture."
        let originalID = try savedTask(goal: goal, in: project, conversationID: conversationID)
        let provider = VyronContinuationEffortTestProvider(selectionError: .http(503))
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: conversationID,
            responseID: UUID(),
            continuation: VyronDevelopmentContinuationContext(originalGoal: goal, priorResponseIDs: [originalID])
        ))

        do {
            _ = try await agent.run(
                goal: "Continue", model: "preferred-coder",
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("A model-selection failure must propagate.")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .http(503))
        }

        let saved = try XCTUnwrap(taskStore(in: project, conversationID: conversationID).load(id: originalID))
        XCTAssertEqual(saved.status, .failed)
        let steps = await provider.recordedStepEfforts()
        XCTAssertTrue(steps.isEmpty)
    }

    private func savedTask(
        goal: String,
        in project: DevelopmentWorkspace,
        conversationID: UUID,
        guidance: [String] = []
    ) throws -> UUID {
        var task = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: UUID(), projectPath: project.rootURL.path, originalGoal: goal
        ))
        for value in guidance { try task.recordGuidance(value) }
        task.finish(.failed, detail: "The previous response did not finish its original task.")
        try taskStore(in: project, conversationID: conversationID).save(task)
        return task.identity.id
    }

    private func taskStore(
        in project: DevelopmentWorkspace,
        conversationID: UUID
    ) throws -> VyronDevelopmentTaskStore {
        try VyronDevelopmentTaskStore(
            directoryURL: project.taskStateDirectoryURL.appendingPathComponent(conversationID.uuidString),
            projectPath: project.rootURL.path
        )
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronContinuationEffort-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }
}
