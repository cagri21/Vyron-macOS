import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

final class VyronDevelopmentCompletionTests: XCTestCase, @unchecked Sendable {
    func testSourceWriteWithoutPlanCannotFinishBeforeVerification() async throws {
        try await assertIncompleteSourceWrite(repeatsSameWrite: false)
    }

    func testSameContentNoOpCannotEraseUnverifiedSourceMutation() async throws {
        try await assertIncompleteSourceWrite(repeatsSameWrite: true)
    }

    func testPendingPlanFinalDeferralKeepsSteeringOpenUntilStageActuallyFinishes() async throws {
        let project = try workspace()
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Keep the original API unchanged while finishing the review.")
        let accepted = VyronSteeringTestLog<Bool>()
        let applied = VyronSteeringTestLog<VyronSteeringMessage>()
        let pending = plan(status: .inProgress)
        let completed = plan(status: .completed)
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1:
                return DevelopmentMessage(role: "assistant", toolCalls: [pending])
            case 2:
                return DevelopmentMessage(role: "assistant", content: "Premature final with an unfinished stage.")
            case 3:
                accepted.append(await inbox.append(update))
                return DevelopmentMessage(role: "assistant", content: "Superseded stage final.")
            case 4:
                return DevelopmentMessage(role: "assistant", toolCalls: [completed])
            default:
                return DevelopmentMessage(role: "assistant", content: "The read-only review is complete.")
            }
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Review the project API without changing files.",
            model: "fixture-coder",
            steeringInbox: inbox,
            onSteeringApplied: { applied.append($0) },
            onEvent: { _ in },
            approveCommand: { _ in false }
        )

        XCTAssertEqual(accepted.values, [true], "A final deferral must leave the active run's inbox open")
        XCTAssertEqual(applied.values, [update])
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 5)
        let requestAfterSteering = try XCTUnwrap(requests.dropFirst(3).first)
        XCTAssertTrue(requestAfterSteering.contains { $0.role == "user" && $0.content == update.content })
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.changedFiles.isEmpty)
        let acceptedAfterCompletion = await inbox.append(update)
        XCTAssertFalse(acceptedAfterCompletion, "Only the actual completed run must refuse late steering")
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronCompletion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }

    private func assertIncompleteSourceWrite(repeatsSameWrite: Bool) async throws {
        let project = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let write = DevelopmentToolCall(
            name: "write_file",
            arguments: ["path": .string("Feature.swift"), "content": .string("let value = 1\n")],
            id: "source-write"
        )
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1 || (repeatsSameWrite && round == 2)
                ? DevelopmentMessage(role: "assistant", toolCalls: [write])
                : DevelopmentMessage(role: "assistant", content: "Created the source fixture.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(session)

        let result = try await agent.run(
            goal: "Create a Swift source fixture; no executable target or verification command is available.",
            model: "fixture-coder",
            onEvent: { _ in },
            approveCommand: { _ in XCTFail("This fixture must not run commands"); return false }
        )

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.changedFiles, ["Feature.swift"])
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.finalMessage.contains("Source verification remains unfinished."))
        XCTAssertFalse(result.finalMessage.contains("Verification: no build or test command was run."))
        XCTAssertFalse(result.finalMessage.contains("Changed files:"))
        let store = try checkpointStore(project: project, session: session)
        let checkpoint = try XCTUnwrap(store.load(id: session.responseID))
        XCTAssertEqual(checkpoint.status, .interrupted)
        XCTAssertTrue(checkpoint.plan.isEmpty, "Omitting update_plan must not bypass source verification")
        XCTAssertEqual(checkpoint.progress.files.map(\.path), ["Feature.swift"])
        XCTAssertEqual(checkpoint.progress.files.first?.status, .saved)
        let requests = await provider.recordedRequests()
        XCTAssertLessThanOrEqual(requests.count, 5, "An unavailable check must leave a bounded, resumable result")
    }

    private func plan(status: VyronDevelopmentPlanStepStatus) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "update_plan", arguments: ["plan": .array([
            .object(["step": .string("Review the public API"), "status": .string(status.rawValue)])
        ])], id: "review-\(status.rawValue)")
    }

    private func checkpointStore(
        project: DevelopmentWorkspace,
        session: VyronDevelopmentSessionContext
    ) throws -> VyronDevelopmentTaskStore {
        try VyronDevelopmentTaskStore(
            directoryURL: project.taskStateDirectoryURL.appendingPathComponent(session.conversationID.uuidString),
            projectPath: project.rootURL.path
        )
    }
}
