import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentEmptyResponseRecoveryTests: XCTestCase {
    func testEmptyStepRetriesInferenceAndPreservesTheOriginalRequest() async throws {
        let goal = "Explain the current project without changing any files."
        let provider = VyronSteeringTestProvider { round, _ in
            DevelopmentMessage(role: "assistant", content: round == 1 ? " \n\t" : "The project is ready to inspect.")
        }

        let result = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: goal, model: "fixture-coder",
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.contains { $0.role == "user" && $0.content == goal } })
        XCTAssertTrue(requests[1].contains { $0.role == "system" && $0.content.contains("previous inference") })
        XCTAssertTrue(result.finalMessage.contains("The project is ready to inspect."))
        XCTAssertTrue(result.isComplete)
    }

    func testRepeatedEmptyStepsStopAfterTwoRecoveryRetries() async throws {
        let provider = VyronSteeringTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", content: " \n\t")
        }

        do {
            _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
                goal: "Inspect the project.", model: "fixture-coder",
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("An empty provider response must not complete the task.")
        } catch DevelopmentAgentError.invalidTool(let detail) {
            XCTAssertTrue(detail.contains("no answer or native tool call"))
        }

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 3)
    }

    func testEmptyAndContextFailuresShareTheSameRecoveryAllowance() async throws {
        let provider = VyronSteeringTestProvider { round, _ in
            if round == 2 { throw DevelopmentAgentError.contextBudget }
            return DevelopmentMessage(role: "assistant", content: "")
        }

        do {
            _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
                goal: "Inspect the project.", model: "fixture-coder",
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("Mixed inference failures must not start an additional recovery allowance.")
        } catch DevelopmentAgentError.invalidTool(let detail) {
            XCTAssertTrue(detail.contains("bounded recovery"))
        }

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 3)
    }

    func testRecoveryRetainsRecordedExternalActionAndDoesNotExecuteItAgain() async throws {
        let original = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "original-action")
        let repeated = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "repeated-action")
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1: return DevelopmentMessage(role: "assistant", toolCalls: [original])
            case 2: return DevelopmentMessage(role: "assistant", content: "")
            case 3: return DevelopmentMessage(role: "assistant", toolCalls: [repeated])
            default: return DevelopmentMessage(role: "assistant", content: "The resource exists once.")
            }
        }

        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Create exactly one fixture resource.", model: "fixture-coder",
            externalTools: [DevelopmentExternalTool(
                name: "mcp_fixture_write", description: "Create one fixture resource",
                inputSchema: ["type": .string("object")], isReadOnly: false
            )],
            executeExternalTool: { call in
                executed.append(call)
                return DevelopmentExternalResult(text: "Created resource-exact-id-42")
            },
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertEqual(executed.values, [original])
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests[2].contains { $0.content.contains("resource-exact-id-42") })
        let saved = try XCTUnwrap(requests[3].first { $0.toolCallID == repeated.id })
        XCTAssertTrue(saved.content.contains("resource-exact-id-42"))
        XCTAssertTrue(saved.content.contains("\"ok\":true"))
    }

    func testCancellationAtEmptyStepPreventsAnotherInferenceRequest() async throws {
        let provider = VyronSteeringTestProvider { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return DevelopmentMessage(role: "assistant", content: "")
        }
        let agent = try DevelopmentAgent(client: provider, workspace: workspace())
        let execution = Task {
            try await agent.run(
                goal: "Inspect the project.", model: "fixture-coder",
                onEvent: { _ in }, approveCommand: { _ in false }
            )
        }

        do {
            _ = try await execution.value
            XCTFail("Cancellation must propagate before another inference attempt.")
        } catch is CancellationError {
            let requests = await provider.recordedRequests()
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testNewGuidanceDuringRecoveryPreventsAStaleToolAction() async throws {
        let project = try workspace()
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Do not create any files; explain the next steps instead.")
        let acknowledged = VyronSteeringTestLog<UUID>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1:
                await inbox.append(update)
                return DevelopmentMessage(role: "assistant", content: "")
            case 2:
                return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                    name: "write_file",
                    arguments: ["path": .string("MustNotExist.txt"), "content": .string("stale action")]
                )])
            default:
                return DevelopmentMessage(role: "assistant", content: "Here are the next steps without file changes.")
            }
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Create a project note.", model: "fixture-coder", steeringInbox: inbox,
            onSteeringApplied: { acknowledged.append($0.id) },
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        XCTAssertTrue(result.changedFiles.isEmpty)
        let staleFile = project.rootURL.appendingPathComponent("MustNotExist.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFile.path))
        XCTAssertEqual(acknowledged.values, [update.id])
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests[2].contains { $0.role == "user" && $0.content.contains(update.content) })
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronEmptyResponseRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }
}
