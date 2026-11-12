import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

final class VyronDevelopmentMilestoneTests: XCTestCase, @unchecked Sendable {
    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronMilestone-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }

    private func plan(_ title: String, status: VyronDevelopmentPlanStepStatus) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "update_plan", arguments: ["plan": .array([
            .object(["step": .string(title), "status": .string(status.rawValue)])
        ])], id: "plan-\(status.rawValue)")
    }

    private func store(
        project: DevelopmentWorkspace,
        session: VyronDevelopmentSessionContext
    ) throws -> VyronDevelopmentTaskStore {
        try VyronDevelopmentTaskStore(
            directoryURL: project.taskStateDirectoryURL.appendingPathComponent(session.conversationID.uuidString),
            projectPath: project.rootURL.path
        )
    }

    private func savedTask(
        project: DevelopmentWorkspace,
        session: VyronDevelopmentSessionContext,
        goal: String
    ) throws -> VyronDevelopmentTaskState {
        var state = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: session.responseID, projectPath: project.rootURL.path, originalGoal: goal
        ))
        try state.updatePlan(VyronDevelopmentPlanUpdate(steps: [
            VyronDevelopmentPlanStep(title: "Other task's unfinished stage", status: .inProgress)
        ]))
        state.finish(.interrupted, detail: "Saved for later continuation")
        return state
    }

    func testMixedPlanAndWriteBatchSkipsWriteRegardlessOfCallOrder() async throws {
        let start = plan("Review requested change", status: .inProgress)
        let finish = plan("Review requested change", status: .completed)
        let write = DevelopmentToolCall(name: "write_file", arguments: [
            "path": .string("stale.md"), "content": .string("Must be reconsidered after planning")
        ], id: "stale-write")
        for batch in [[start, write], [write, start]] {
            let project = try workspace()
            let provider = VyronSteeringTestProvider { round, _ in
                switch round {
                case 1: return DevelopmentMessage(role: "assistant", toolCalls: batch)
                case 2: return DevelopmentMessage(role: "assistant", toolCalls: [finish])
                default: return DevelopmentMessage(role: "assistant", content: "Reviewed the request.")
                }
            }

            let result = try await DevelopmentAgent(client: provider, workspace: project).run(
                goal: "Record a plan first, then reconsider the proposed write.",
                model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false }
            )

            XCTAssertFalse(FileManager.default.fileExists(atPath: project.rootURL.appendingPathComponent("stale.md").path))
            XCTAssertTrue(result.changedFiles.isEmpty)
            let requests = await provider.recordedRequests()
            XCTAssertEqual(requests.count, 3)
            let skipped = try XCTUnwrap(requests[1].first { $0.toolCallID == "stale-write" })
            XCTAssertTrue(skipped.content.contains("Not executed"))
            XCTAssertEqual(requests[1].filter { $0.role == "tool" }.map(\.toolCallID), batch.map(\.id))
        }
    }

    func testResumedSourceStageCannotCompleteWithoutCurrentVerification() async throws {
        let project = try workspace()
        let original = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let resumed = VyronDevelopmentSessionContext(conversationID: original.conversationID, responseID: UUID())
        let goal = "Implement the saved feature."
        let content = "let feature = true\n"
        let path = "Feature.swift"
        try Data(content.utf8).write(to: project.rootURL.appendingPathComponent(path))
        var state = try savedTask(project: project, session: original, goal: goal)
        try state.updatePlan(VyronDevelopmentPlanUpdate(steps: [
            VyronDevelopmentPlanStep(title: "Implement feature", status: .inProgress)
        ]))
        try state.recordFile(VyronDevelopmentFileProgress(
            path: path,
            contentHash: VyronDevelopmentFileProgress.hash(content: content),
            status: .saved,
            recordedAt: Date()
        ))
        let taskStore = try store(project: project, session: original)
        try taskStore.save(state)
        let completed = plan("Implement feature", status: .completed)
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1
                ? DevelopmentMessage(role: "assistant", toolCalls: [completed])
                : DevelopmentMessage(role: "assistant", content: "Verification is unavailable.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(resumed)

        let result = try await agent.run(
            goal: goal, model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        let refusal = try XCTUnwrap(requests[1].first { $0.toolCallID == completed.id })
        XCTAssertTrue(refusal.content.contains("\"ok\":false"))
        XCTAssertTrue(refusal.content.lowercased().contains("verif"))
        XCTAssertFalse(result.isComplete)
        let checkpoint = try XCTUnwrap(taskStore.load(id: original.responseID))
        XCTAssertEqual(checkpoint.plan.first?.status, .inProgress)
        XCTAssertEqual(checkpoint.status, .interrupted)
        XCTAssertTrue(checkpoint.progress.checks.isEmpty)
        XCTAssertNil(try taskStore.load(id: resumed.responseID))
    }

    func testCheckpointDoesNotCrossConversationBoundaryEvenForIdenticalGoals() async throws {
        let project = try workspace()
        let original = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let other = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let goal = "Inspect this project."
        let state = try savedTask(project: project, session: original, goal: goal)
        let originalStore = try store(project: project, session: original)
        try originalStore.save(state)
        let provider = VyronSteeringTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", content: "Inspected the project.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(other)

        let result = try await agent.run(
            goal: goal, model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(requests[0].map(\.content).joined().contains("Other task's unfinished stage"))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(try originalStore.load(id: original.responseID), state)
        let otherStore = try store(project: project, session: other)
        let checkpoint = try XCTUnwrap(otherStore.load(id: other.responseID))
        XCTAssertEqual(checkpoint.status, .completed)
        XCTAssertTrue(checkpoint.plan.isEmpty)
    }

    func testCheckpointDoesNotCrossProjectBoundaryForSameConversation() async throws {
        let originalProject = try workspace()
        let otherProject = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let goal = "Inspect this project."
        let state = try savedTask(project: originalProject, session: session, goal: goal)
        let originalStore = try store(project: originalProject, session: session)
        try originalStore.save(state)
        let provider = VyronSteeringTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", content: "Inspected the selected project.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: otherProject)
        try await agent.configureSession(session)

        let result = try await agent.run(
            goal: goal, model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertFalse(requests[0].map(\.content).joined().contains("Other task's unfinished stage"))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(try originalStore.load(id: session.responseID), state)
        let otherStore = try store(project: otherProject, session: session)
        let checkpoint = try XCTUnwrap(otherStore.load(id: session.responseID))
        XCTAssertEqual(checkpoint.identity.projectPath, otherProject.rootURL.path)
        XCTAssertTrue(checkpoint.plan.isEmpty)
    }

    func testChangingListLimitsWithoutNewEvidenceStopsAfterRecovery() async throws {
        let project = try workspace()
        let provider = VyronSteeringTestProvider { round, _ in
            DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                name: "list_files", arguments: ["limit": .number(Double(round))], id: "round-\(round)"
            )])
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Inspect the project until the current task allowance is reached.",
            model: "fixture-coder", effort: .quick,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertLessThanOrEqual(requests.count, 5)
        XCTAssertEqual(result.steps, requests.count)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertFalse(result.finalMessage.isEmpty)
    }

    func testExplicitResumePreservesCurrentScopeAndDoesNotReplayRecordedExternalAction() async throws {
        let project = try workspace()
        let original = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let resumed = VyronDevelopmentSessionContext(conversationID: original.conversationID, responseID: UUID())
        let latestGoal = "Continue the saved task, but inspect only and preserve the current API."
        let call = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "already-created")
        var state = try savedTask(project: project, session: original, goal: "Implement the complete feature.")
        try state.recordGuidance("Keep the original public contract.")
        try state.recordIntegration(VyronDevelopmentIntegrationProgress(
            identity: VyronDevelopmentIntegrationIdentity(
                toolName: call.function.name,
                argumentsHash: try VyronDevelopmentRunControl.callKey(call)
            ),
            status: .succeeded,
            summary: "Created resource-exact-id-42"
        ))
        let taskStore = try store(project: project, session: original)
        try taskStore.save(state)
        let resume = DevelopmentToolCall(name: "resume_task", arguments: [:], id: "restore-task")
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1: return DevelopmentMessage(role: "assistant", toolCalls: [resume])
            case 2: return DevelopmentMessage(role: "assistant", toolCalls: [call])
            default: return DevelopmentMessage(role: "assistant", content: "The unfinished stage needs further review.")
            }
        }
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(resumed)

        let result = try await agent.run(
            goal: latestGoal, model: "fixture-coder",
            externalTools: [DevelopmentExternalTool(
                name: "mcp_fixture_write", description: "Create one fixture resource",
                inputSchema: ["type": .string("object")], isReadOnly: false
            )],
            executeExternalTool: { call in
                executed.append(call)
                return DevelopmentExternalResult(text: "Must not execute again")
            },
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        XCTAssertTrue(executed.values.isEmpty)
        XCTAssertFalse(result.isComplete)
        let checkpoint = try XCTUnwrap(taskStore.load(id: original.responseID))
        XCTAssertTrue(checkpoint.guidance.contains("Keep the original public contract."))
        XCTAssertTrue(checkpoint.guidance.contains { $0.contains(latestGoal) })
        XCTAssertEqual(checkpoint.progress.integrations, state.progress.integrations)
        let requests = await provider.recordedRequests()
        let skipped = try XCTUnwrap(requests[2].first { $0.toolCallID == call.id })
        XCTAssertTrue(skipped.content.contains("\"ok\":true"))
        XCTAssertTrue(skipped.content.contains("resource-exact-id-42"))
    }

    func testRepeatedResumeCannotCompleteRestoredCheckpointOrDiscardNewGuidance() throws {
        let project = try workspace()
        let original = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let resumed = VyronDevelopmentSessionContext(conversationID: original.conversationID, responseID: UUID())
        let state = try savedTask(project: project, session: original, goal: "Implement the original feature.")
        let taskStore = try store(project: project, session: original)
        try taskStore.save(state)
        var progress = try VyronDevelopmentRunProgress(workspace: project, session: resumed, goal: "Continue inspection only.")
        try progress.state.recordGuidance("Do not change the existing file layout.")
        try progress.save()

        try progress.resumePreviousTask()
        try progress.resumePreviousTask()

        let checkpoint = try XCTUnwrap(taskStore.load(id: original.responseID))
        XCTAssertEqual(checkpoint.status, .running)
        XCTAssertEqual(checkpoint.plan, state.plan)
        XCTAssertTrue(checkpoint.guidance.contains { $0.contains("Continue inspection only.") })
        XCTAssertTrue(checkpoint.guidance.contains("Do not change the existing file layout."))
    }
}
