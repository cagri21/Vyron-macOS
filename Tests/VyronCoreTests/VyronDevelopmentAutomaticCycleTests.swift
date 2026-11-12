import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentAutomaticCycleTests: XCTestCase {
    func testUsefulWorkContinuesBeyondOneCycleWithoutReplacingTheOriginalTask() async throws {
        let project = try workspace(noteCount: 16)
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let goal = "Read all sixteen project notes and summarize the findings."
        let calls = (1...16).map { readNote($0) }
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = VyronAutomaticCycleTestProvider { round, _ in
            round <= calls.count
                ? DevelopmentMessage(role: "assistant", toolCalls: [calls[round - 1]])
                : DevelopmentMessage(role: "assistant", content: "All sixteen distinct notes were reviewed.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(session)

        let result = try await agent.run(
            goal: goal, model: "manual-coder", automaticModelSelection: false, effort: .quick,
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        let selections = await provider.recordedSelections()
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.steps, 17)
        XCTAssertEqual(requests.count, 17)
        XCTAssertEqual(selections, [VyronContinuationModelSelection(
            model: "manual-coder", automaticModelSelection: false, effort: .quick
        )])
        XCTAssertTrue(requests.allSatisfy {
            $0.model == "manual-coder" && $0.effort == .quick && $0.mode == .agent
        })
        XCTAssertTrue(requests.allSatisfy { request in
            request.messages.contains { $0.role == "user" && $0.content.contains(goal) }
        })
        XCTAssertTrue(events.values.contains {
            $0.kind == .status && $0.message == "Continuing unfinished work"
        })
        let checkpoint = try checkpoint(project: project, session: session)
        XCTAssertEqual(checkpoint.identity.id, session.responseID)
        XCTAssertEqual(checkpoint.identity.originalGoal, goal)
        XCTAssertEqual(checkpoint.status, .completed)
        XCTAssertTrue(checkpoint.guidance.isEmpty, "Automatic cycles must not fabricate user Continue requests")
    }

    func testRepeatedReadReceivesRecoveryGuidanceAndStillStopsWithinABoundedRun() async throws {
        let project = try workspace(noteCount: 1)
        let call = readNote(1)
        let provider = VyronAutomaticCycleTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", toolCalls: [call])
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Review this project note without repeating completed reads.",
            model: "fixture-coder", effort: .quick,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertFalse(result.isComplete)
        XCTAssertLessThanOrEqual(requests.count, 5)
        XCTAssertTrue(requests.dropFirst().contains { request in
            request.messages.contains { message in
                message.role == "system"
                    && message.content.lowercased().contains("different approach")
            }
        }, "Recovery must tell the model to change its approach before interrupting the task")
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertTrue(result.commands.isEmpty)
    }

    func testCancellationAtAutomaticContinuationPreventsTheNextInferenceAndSavesStoppedState() async throws {
        let project = try workspace(noteCount: 12)
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let calls = (1...12).map { readNote($0) }
        let provider = VyronAutomaticCycleTestProvider { round, _ in
            round <= calls.count
                ? DevelopmentMessage(role: "assistant", toolCalls: [calls[round - 1]])
                : DevelopmentMessage(role: "assistant", content: "All notes were reviewed.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(session)

        let execution = Task {
            try await agent.run(
                goal: "Read the twelve notes and report your conclusion.",
                model: "fixture-coder", effort: .quick,
                onEvent: { event in
                    if event.kind == .status && event.message == "Continuing unfinished work" {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                },
                approveCommand: { _ in false }
            )
        }
        do {
            _ = try await execution.value
            XCTFail("Canceling at the work-cycle boundary must stop the same active task")
        } catch is CancellationError {
            let requests = await provider.recordedRequests()
            XCTAssertEqual(requests.count, 12)
            let checkpoint = try checkpoint(project: project, session: session)
            XCTAssertEqual(checkpoint.identity.id, session.responseID)
            XCTAssertEqual(checkpoint.status, .stopped)
        }
    }

    func testPrematureFinalRequestsVerificationWithoutClaimingSourceCompletion() async throws {
        let project = try workspace(noteCount: 0)
        let write = DevelopmentToolCall(name: "write_file", arguments: [
            "path": .string("Feature.swift"), "content": .string("let value = 1\n")
        ])
        let provider = VyronAutomaticCycleTestProvider { round, _ in
            round == 1
                ? DevelopmentMessage(role: "assistant", toolCalls: [write])
                : DevelopmentMessage(role: "assistant", content: "The source fixture is complete.")
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Create a Swift fixture and verify it before declaring the task complete.",
            model: "fixture-coder", effort: .quick,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertFalse(result.isComplete)
        XCTAssertGreaterThan(
            requests.count, 2, "A premature final should first receive actionable verification feedback"
        )
        XCTAssertLessThanOrEqual(requests.count, 5)
        XCTAssertTrue(requests.dropFirst(2).contains { request in
            request.messages.contains { message in
                message.role == "system" && message.content.lowercased().contains("verification")
            }
        })
        XCTAssertTrue(result.finalMessage.contains("Source verification remains unfinished."))
        XCTAssertEqual(result.changedFiles, ["Feature.swift"])
    }

    private func workspace(noteCount: Int) throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronAutomaticCycle-\(UUID().uuidString)", isDirectory: true)
        let notes = directory.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        if noteCount > 0 {
            for index in 1...noteCount {
                try Data("Project note \(index) contains distinct evidence \(index * 17).\n".utf8)
                    .write(to: notes.appendingPathComponent("note-\(index).txt"))
            }
        }
        return try DevelopmentWorkspace(rootURL: directory)
    }

    private func readNote(_ index: Int) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Notes/note-\(index).txt")])
    }

    private func checkpoint(
        project: DevelopmentWorkspace,
        session: VyronDevelopmentSessionContext
    ) throws -> VyronDevelopmentTaskState {
        let store = try VyronDevelopmentTaskStore(
            directoryURL: project.taskStateDirectoryURL.appendingPathComponent(session.conversationID.uuidString),
            projectPath: project.rootURL.path
        )
        return try XCTUnwrap(store.load(id: session.responseID))
    }
}
