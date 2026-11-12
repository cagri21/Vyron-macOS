import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

final class VyronDevelopmentRecoveryTests: XCTestCase, @unchecked Sendable {
    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }

    private func write(_ path: String, content: String, id: String) -> DevelopmentToolCall {
        DevelopmentToolCall(
            name: "write_file",
            arguments: ["path": .string(path), "content": .string(content)],
            id: id
        )
    }

    private func externalTool() -> DevelopmentExternalTool {
        DevelopmentExternalTool(
            name: "mcp_fixture_write",
            description: "Create one fixture resource",
            inputSchema: ["type": .string("object")],
            isReadOnly: false
        )
    }

    func testOversizedQuoteHeavyWriteBatchFinishesAndCompactsBeforeNextInference() async throws {
        let project = try workspace()
        let content = String(repeating: "<label text=\"A \\ B &amp; 東京\"/>\n", count: 160)
        let calls = (0..<4).map {
            write("Scene\($0).storyboard", content: content, id: "scene-\($0)")
        }
        let batch = DevelopmentMessage(role: "assistant", toolCalls: calls)
        XCTAssertGreaterThan(try JSONEncoder().encode(batch).count, 24_000)
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1 ? batch : DevelopmentMessage(role: "assistant", content: "Created the storyboard fixtures.")
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Create four storyboard fixtures; this folder has no executable build target.",
            model: "fixture-coder",
            onEvent: { events.append($0) },
            approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 4, "Source completion first receives two bounded verification reminders")
        XCTAssertLessThanOrEqual(try JSONEncoder().encode(requests[1]).count, 24_000)
        XCTAssertEqual(Set(result.changedFiles), Set((0..<4).map { "Scene\($0).storyboard" }))
        XCTAssertEqual(events.values.filter { $0.kind == .fileChanged }.count, 4)
        let context = requests[1].map(\.content).joined(separator: "\n")
        for index in 0..<4 {
            let path = "Scene\(index).storyboard"
            XCTAssertEqual(
                try String(contentsOf: project.rootURL.appendingPathComponent(path), encoding: .utf8),
                content
            )
            XCTAssertTrue(context.contains(path), "Compaction must retain which files actually succeeded")
        }
    }

    func testContextRecoveryDoesNotReplaySuccessfulExternalActionAndRetainsItsIdentity() async throws {
        let call = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "created-once")
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1:
                return DevelopmentMessage(role: "assistant", toolCalls: [call])
            case 2:
                throw DevelopmentAgentError.contextBudget
            default:
                return DevelopmentMessage(role: "assistant", content: "The resource was created once.")
            }
        }

        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Create one fixture resource and retain its exact identity.",
            model: "fixture-coder",
            externalTools: [externalTool()],
            executeExternalTool: { call in
                executed.append(call)
                return DevelopmentExternalResult(text: "Created resource: resource-exact-id-42")
            },
            onEvent: { _ in },
            approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertEqual(executed.values, [call])
        XCTAssertEqual(requests.count, 3)
        let recovered = requests[2].map(\.content).joined(separator: "\n")
        XCTAssertTrue(recovered.contains("resource-exact-id-42"))
        XCTAssertTrue(recovered.contains("Create one fixture resource"))
    }

    func testRepeatedContextFailureStopsAfterTwoRecoveryRetries() async throws {
        let provider = VyronSteeringTestProvider { _, _ in
            throw DevelopmentAgentError.contextBudget
        }

        do {
            _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
                goal: "Inspect this project.",
                model: "fixture-coder",
                onEvent: { _ in },
                approveCommand: { _ in false }
            )
        } catch DevelopmentAgentError.contextBudget {
            // An irreducible request can still fail after bounded recovery.
        }

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.contains { $0.role == "user" && $0.content.contains("Inspect") } })
    }

    func testRepeatedExternalCallAfterRecoveryUsesSavedSuccessInsteadOfExecutingAgain() async throws {
        let first = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "original-action")
        let repeated = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "repeated-action")
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1: return DevelopmentMessage(role: "assistant", toolCalls: [first])
            case 2: throw DevelopmentAgentError.contextBudget
            case 3: return DevelopmentMessage(role: "assistant", toolCalls: [repeated])
            default: return DevelopmentMessage(role: "assistant", content: "The single resource is ready.")
            }
        }

        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Create exactly one fixture resource.", model: "fixture-coder",
            externalTools: [externalTool()],
            executeExternalTool: { call in
                executed.append(call)
                return DevelopmentExternalResult(text: "Created resource-exact-id-42")
            },
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertEqual(executed.values, [first])
        XCTAssertEqual(requests.count, 4)
        let saved = try XCTUnwrap(requests[3].first { $0.toolCallID == "repeated-action" })
        XCTAssertTrue(saved.content.contains("\"ok\":true"))
        XCTAssertTrue(saved.content.contains("resource-exact-id-42"))
    }

    func testNulInSuccessfulIntegrationOutputCannotTurnSuccessIntoAReplayableFailure() async throws {
        let call = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "nul-output")
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let provider = VyronSteeringTestProvider { round, _ in
            round <= 2
                ? DevelopmentMessage(role: "assistant", toolCalls: [call])
                : DevelopmentMessage(role: "assistant", content: "The resource was created.")
        }

        do {
            _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
                goal: "Create exactly one fixture resource.", model: "fixture-coder",
                externalTools: [externalTool()],
                executeExternalTool: { call in
                    executed.append(call)
                    return DevelopmentExternalResult(text: "Created\0 resource-exact-id-42")
                },
                onEvent: { _ in }, approveCommand: { _ in false }
            )
        } catch is VyronDevelopmentCheckpointFailure {
            // If evidence cannot be saved, stop before an action can be repeated.
        }

        XCTAssertEqual(executed.values, [call])
        let requests = await provider.recordedRequests()
        if requests.count > 1 {
            let recorded = try XCTUnwrap(requests[1].first { $0.toolCallID == "nul-output" })
            XCTAssertTrue(recorded.content.contains("\"ok\":true"))
        }
    }

    func testCancellationAfterIntegrationSuccessSavesItsOutcomeBeforeStopping() async throws {
        let project = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let call = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "succeeded-before-stop")
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let provider = VyronSteeringTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", toolCalls: [call])
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(session)
        let execution = Task {
            try await agent.run(
                goal: "Create one fixture resource.", model: "fixture-coder",
                externalTools: [externalTool()],
                executeExternalTool: { call in
                    executed.append(call)
                    withUnsafeCurrentTask { $0?.cancel() }
                    return DevelopmentExternalResult(text: "Created resource-exact-id-42")
                },
                onEvent: { _ in }, approveCommand: { _ in false }
            )
        }

        do {
            _ = try await execution.value
            XCTFail("Stop must prevent further inference after the successful action")
        } catch is CancellationError {
            let store = try VyronDevelopmentTaskStore(
                directoryURL: project.taskStateDirectoryURL.appendingPathComponent(session.conversationID.uuidString),
                projectPath: project.rootURL.path
            )
            let saved = try XCTUnwrap(store.load(id: session.responseID))
            XCTAssertEqual(saved.status, .stopped)
            XCTAssertTrue(saved.progress.integrations.contains {
                $0.succeeded && $0.summary.contains("resource-exact-id-42")
            })
            XCTAssertEqual(executed.values, [call])
            let requests = await provider.recordedRequests()
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testLongSuccessfulIntegrationOutputIsBoundedWithoutInvitingReplay() async throws {
        let call = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "long-output")
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let provider = VyronSteeringTestProvider { round, _ in
            round <= 2
                ? DevelopmentMessage(role: "assistant", toolCalls: [call])
                : DevelopmentMessage(role: "assistant", content: "The single resource is ready.")
        }

        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Create exactly one fixture resource.", model: "fixture-coder",
            externalTools: [externalTool()],
            executeExternalTool: { call in
                executed.append(call)
                return DevelopmentExternalResult(text: "Created resource-exact-id-42\n" + String(repeating: "x", count: 1_500))
            },
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        XCTAssertEqual(executed.values, [call])
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        let recorded = try XCTUnwrap(requests[2].first { $0.toolCallID == "long-output" })
        XCTAssertTrue(recorded.content.contains("\"ok\":true"))
        XCTAssertTrue(recorded.content.contains("resource-exact-id-42"))
    }

    func testCancellationAtBudgetFailurePreventsRecoveryRequest() async throws {
        let provider = VyronSteeringTestProvider { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            throw DevelopmentAgentError.contextBudget
        }
        let agent = try DevelopmentAgent(client: provider, workspace: workspace())
        let execution = Task {
            try await agent.run(
                goal: "Inspect this project.",
                model: "fixture-coder",
                onEvent: { _ in },
                approveCommand: { _ in false }
            )
        }

        do {
            _ = try await execution.value
            XCTFail("Cancellation must propagate before another inference attempt")
        } catch is CancellationError {
            let requests = await provider.recordedRequests()
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testFullReplayLedgerStopsBeforeAnotherExternalActionAndKeepsEarlierSuccesses() async throws {
        let project = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let goal = "Continue the same resource task."
        let store = try VyronDevelopmentTaskStore(
            directoryURL: project.taskStateDirectoryURL.appendingPathComponent(session.conversationID.uuidString),
            projectPath: project.rootURL.path
        )
        var state = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: session.responseID, projectPath: project.rootURL.path, originalGoal: goal
        ))
        for index in 0..<VyronDevelopmentTaskLimits.maximumIntegrations {
            let previous = DevelopmentToolCall(name: "mcp_fixture_write", arguments: ["index": .number(Double(index))])
            try state.recordIntegration(VyronDevelopmentIntegrationProgress(
                identity: VyronDevelopmentIntegrationIdentity(
                    toolName: previous.function.name,
                    argumentsHash: try VyronDevelopmentRunControl.callKey(previous)
                ),
                status: .succeeded,
                summary: "Created resource \(index)"
            ))
        }
        try store.save(state)
        let call = DevelopmentToolCall(name: "mcp_fixture_write", arguments: ["index": .number(999)])
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let provider = VyronSteeringTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", toolCalls: [call])
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(session)

        do {
            _ = try await agent.run(
                goal: goal, model: "fixture-coder", externalTools: [externalTool()],
                executeExternalTool: { call in
                    executed.append(call)
                    return DevelopmentExternalResult(text: "Must not execute")
                },
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("A full replay ledger must stop before a new external side effect")
        } catch is VyronDevelopmentCheckpointFailure {
            XCTAssertTrue(executed.values.isEmpty)
            let saved = try XCTUnwrap(store.load(id: session.responseID))
            XCTAssertEqual(saved.progress.integrations, state.progress.integrations)
            let requests = await provider.recordedRequests()
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testNoOpWriteIsSkippedWhileGenuineRevisionStillApplies() async throws {
        let project = try workspace()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let first = write("Feature.swift", content: "let version = 1\n", id: "first")
        let repeated = write("Feature.swift", content: "let version = 1\n", id: "same-content")
        let revised = write("Feature.swift", content: "let version = 2\n", id: "revision")
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1: return DevelopmentMessage(role: "assistant", toolCalls: [first])
            case 2: return DevelopmentMessage(role: "assistant", toolCalls: [repeated])
            case 3: return DevelopmentMessage(role: "assistant", toolCalls: [revised])
            default: return DevelopmentMessage(role: "assistant", content: "Applied the revised value.")
            }
        }

        _ = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Create a fixture and revise its value after checking the first version.",
            model: "fixture-coder",
            onEvent: { events.append($0) },
            approveCommand: { _ in false }
        )

        XCTAssertEqual(
            try String(contentsOf: project.rootURL.appendingPathComponent("Feature.swift"), encoding: .utf8),
            "let version = 2\n"
        )
        XCTAssertEqual(events.values.filter { $0.kind == .fileChanged }.count, 2)
        let requests = await provider.recordedRequests()
        let duplicateResult = try XCTUnwrap(requests[2].first { $0.toolCallID == "same-content" })
        XCTAssertTrue(duplicateResult.content.contains("\"ok\":true"))
    }

    func testStagnantWriteLoopStopsBeforeToolRoundLimitWithoutRepeatedEdits() async throws {
        let project = try workspace()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let call = write("Feature.swift", content: "let value = 1\n", id: "repeated-write")
        let provider = VyronSteeringTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", toolCalls: [call])
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Create one source fixture.",
            model: "fixture-coder",
            onEvent: { events.append($0) },
            approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertGreaterThan(requests.count, 1)
        XCTAssertLessThanOrEqual(requests.count, 6)
        XCTAssertEqual(events.values.filter { $0.kind == .fileChanged }.count, 1)
        XCTAssertEqual(result.changedFiles, ["Feature.swift"])
        XCTAssertFalse(result.finalMessage.isEmpty)
    }
}
