import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentCycleSafetyTests: XCTestCase {
    func testAutomaticContinuationDoesNotRenewAnExhaustedCheckAllowance() async throws {
        let project = try workspace()
        try Data("let broken: Int = \"invalid\"\n".utf8)
            .write(to: project.rootURL.appendingPathComponent("Broken.swift"))
        let command = DevelopmentToolCall(
            name: "run_command", arguments: ["command": .string("swiftc -typecheck Broken.swift")]
        )
        let reads = (1...9).map { readNote($0) }
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1, 3, 5, 13:
                return DevelopmentMessage(role: "assistant", toolCalls: [command])
            case 2:
                return DevelopmentMessage(role: "assistant", toolCalls: [reads[0]])
            case 4:
                return DevelopmentMessage(role: "assistant", toolCalls: [reads[1]])
            case 6...12:
                return DevelopmentMessage(role: "assistant", toolCalls: [reads[round - 4]])
            default:
                return DevelopmentMessage(role: "assistant", content: "The requested check remains unsuccessful.")
            }
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureCommandApproval(.fullAccess)

        let result = try await agent.run(
            goal: "Check the broken source and review the notes; report any unresolved failure.",
            model: "fixture-coder", effort: .quick,
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )

        // This protects the attempt allowance even when local command execution is unavailable.
        // No successful compiler execution is inferred from a protected or failed attempt.
        XCTAssertEqual(result.commands.count, 3)
        XCTAssertTrue(result.commands.allSatisfy { !$0.succeeded })
        XCTAssertEqual(events.values.filter { $0.kind == .commandStarted }.count, 3)
        XCTAssertTrue(events.values.contains { $0.message == "Continuing unfinished work" })
        let requests = await provider.recordedRequests()
        let refusal = try XCTUnwrap(requests[13].last { $0.toolName == "run_command" })
        let value = try JSONDecoder().decode(DevelopmentJSONValue.self, from: Data(refusal.content.utf8))
        guard case .object(let payload) = value, case .string(let output) = payload["output"] else {
            return XCTFail("The exhausted check allowance must return a native tool refusal")
        }
        XCTAssertEqual(payload["ok"], .bool(false))
        XCTAssertTrue(output.contains("three-attempt build/test budget is exhausted"))
        XCTAssertFalse(result.isComplete, "A failed requested check must leave the task unfinished")
    }

    func testDeclinedCommandIsNotRequestedAgainAfterAutomaticContinuation() async throws {
        let project = try workspace()
        let command = DevelopmentToolCall(
            name: "run_command", arguments: ["command": .string("echo never-run")]
        )
        let reads = (1...11).map { readNote($0) }
        let reviews = VyronSteeringTestLog<CommandApproval>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1, 13:
                return DevelopmentMessage(role: "assistant", toolCalls: [command])
            case 2...12:
                return DevelopmentMessage(role: "assistant", toolCalls: [reads[round - 2]])
            default:
                return DevelopmentMessage(
                    role: "assistant", content: "The notes were reviewed without running the command."
                )
            }
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Review the notes and respect any declined command.",
            model: "fixture-coder", effort: .quick,
            onEvent: { events.append($0) },
            approveCommand: { approval in
                reviews.append(approval)
                return false
            }
        )

        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(reviews.values.map(\.command), ["echo never-run"])
        XCTAssertTrue(events.values.contains {
            $0.kind == .status && $0.message == "Continuing unfinished work"
        })
        XCTAssertFalse(events.values.contains { $0.kind == .commandStarted })
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 14)
    }

    func testSuccessfulExternalWriteIsNotReplayedAfterAutomaticContinuation() async throws {
        let project = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let write = DevelopmentToolCall(
            name: "mcp_fixture_write", arguments: ["name": .string("one-resource")], id: "one-write"
        )
        let tool = DevelopmentExternalTool(
            name: "mcp_fixture_write", description: "Create one fixture resource",
            inputSchema: ["type": .string("object")], isReadOnly: false
        )
        let reads = (1...11).map { readNote($0) }
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1, 13:
                return DevelopmentMessage(role: "assistant", toolCalls: [write])
            case 2...12:
                return DevelopmentMessage(role: "assistant", toolCalls: [reads[round - 2]])
            default:
                return DevelopmentMessage(
                    role: "assistant", content: "One resource was created and the notes were reviewed."
                )
            }
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(session)

        let result = try await agent.run(
            goal: "Create one resource and review the project notes without duplicating the resource.",
            model: "fixture-coder", effort: .quick, externalTools: [tool],
            executeExternalTool: { call in
                executed.append(call)
                return DevelopmentExternalResult(text: "Created resource exact-resource-42.")
            },
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(executed.values, [write])
        XCTAssertTrue(events.values.contains {
            $0.kind == .status && $0.message == "Continuing unfinished work"
        })
        let saved = try checkpoint(project: project, session: session)
        XCTAssertEqual(saved.identity.id, session.responseID)
        XCTAssertEqual(saved.status, .completed)
        XCTAssertEqual(saved.progress.integrations.count, 1)
        XCTAssertEqual(saved.progress.integrations.first?.toolName, tool.name)
        XCTAssertEqual(saved.progress.integrations.first?.status, .succeeded)
        XCTAssertTrue(saved.progress.integrations.first?.summary.contains("exact-resource-42") == true)
    }

    func testSteeringAtCycleBoundaryAppliesBeforeNextInferenceAndRemainsUserGuidance() async throws {
        let project = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(
            content: "Keep the review read-only and include the final note in the summary."
        )
        let accepted = VyronSteeringTestLog<Bool>()
        let applied = VyronSteeringTestLog<VyronSteeringMessage>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let reads = (1...12).map { readNote($0) }
        let provider = VyronSteeringTestProvider { round, _ in
            if round == 12 { accepted.append(await inbox.append(update)) }
            return round <= reads.count
                ? DevelopmentMessage(role: "assistant", toolCalls: [reads[round - 1]])
                : DevelopmentMessage(role: "assistant", content: "The revised read-only review is complete.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(session)

        let result = try await agent.run(
            goal: "Review the project notes without changing files.",
            model: "fixture-coder", effort: .quick, steeringInbox: inbox,
            onSteeringApplied: { applied.append($0) },
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )

        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertEqual(accepted.values, [true])
        XCTAssertEqual(applied.values, [update])
        XCTAssertTrue(events.values.contains {
            $0.kind == .status && $0.message == "Continuing unfinished work"
        })
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 13)
        XCTAssertTrue(requests[12].contains { $0.role == "user" && $0.content == update.content })
        let saved = try checkpoint(project: project, session: session)
        XCTAssertEqual(saved.identity.originalGoal, "Review the project notes without changing files.")
        XCTAssertEqual(saved.guidance, [update.content])
        XCTAssertEqual(saved.status, .completed)
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronCycleSafety-\(UUID().uuidString)", isDirectory: true)
        let notes = directory.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        for index in 1...12 {
            try Data("Distinct project note \(index), evidence \(index * 23).\n".utf8)
                .write(to: notes.appendingPathComponent("note-\(index).txt"))
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
