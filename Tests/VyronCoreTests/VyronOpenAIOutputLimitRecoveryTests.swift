import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronOpenAIOutputLimitRecoveryTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testOutputLimitRecoversWithoutReplayingCompletedActionOrIncompleteTools() async throws {
        let original = DevelopmentToolCall(name: "mcp_fixture_create", arguments: [:], id: "created-once")
        let partial = "PARTIAL_RESPONSE_MUST_NOT_ENTER_CONTEXT"
        let first = try VyronResponsesTestSupport.completion([
            VyronResponsesTestSupport.toolOutput("created-once", name: "mcp_fixture_create")
        ])
        let incomplete = try VyronOutputLimitTestSupport.incomplete(output: [
            VyronResponsesTestSupport.textOutput(partial),
            VyronResponsesTestSupport.toolOutput("incomplete-call", name: "mcp_fixture_create")
        ])
        let repeated = try VyronResponsesTestSupport.completion([
            VyronResponsesTestSupport.toolOutput("repeated-call", name: "mcp_fixture_create")
        ])
        let final = try VyronResponsesTestSupport.completion([
            VyronResponsesTestSupport.textOutput("The existing resource is ready.")
        ])
        await VyronResponsesTestURLProtocol.state.reset { request, number in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(body["model"] as? String, VyronResponsesTestSupport.model)
            XCTAssertEqual(body["max_output_tokens"] as? Int, 4_096)
            XCTAssertNil(body["reasoning"], "Recovery retains the selected reasoning policy")
            switch number {
            case 3: return VyronResponsesTestResponse(body: first)
            case 4: return VyronResponsesTestResponse(body: incomplete)
            case 5: return VyronResponsesTestResponse(body: repeated)
            default: return VyronResponsesTestResponse(body: final)
            }
        }
        let workspace = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let agent = DevelopmentAgent(client: try VyronOutputLimitTestSupport.client(
            recorder: VyronOpenAIUsageTestRecorder()
        ), workspace: workspace)
        try await agent.configureSession(session)
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let goal = "Create exactly one fixture resource and report its identity."
        let result = try await agent.run(
            goal: goal, model: VyronResponsesTestSupport.model, automaticModelSelection: false,
            effort: .balanced, externalTools: [externalTool()],
            executeExternalTool: { call in
                executed.append(call)
                return DevelopmentExternalResult(text: "Created resource EXACT_RESOURCE_42.")
            },
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        XCTAssertEqual(executed.values, [original])
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.finalMessage.contains("existing resource"))
        let bodies = try await VyronOutputLimitTestSupport.generationBodies()
        XCTAssertEqual(bodies.count, 4)
        let recovered = try VyronResponsesTestSupport.json(bodies[2]["input"] ?? [])
        XCTAssertTrue(recovered.contains(goal))
        XCTAssertTrue(recovered.contains("EXACT_RESOURCE_42"))
        XCTAssertTrue(recovered.contains("output limit"))
        XCTAssertFalse(recovered.contains(partial))
        XCTAssertFalse(recovered.contains("incomplete-call"))
        XCTAssertTrue(try VyronResponsesTestSupport.json(bodies[3]).contains("not executed again"))
        let store = try VyronDevelopmentTaskStore(
            directoryURL: workspace.taskStateDirectoryURL.appendingPathComponent(session.conversationID.uuidString),
            projectPath: workspace.rootURL.path
        )
        let saved = try XCTUnwrap(store.load(id: session.responseID))
        XCTAssertEqual(saved.progress.integrations.count, 1)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self).contains(partial))
    }

    func testRepeatedOutputLimitsStopAtExistingRecoveryCapAndReportEveryUsage() async throws {
        let incomplete = try VyronOutputLimitTestSupport.incomplete()
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            return VyronResponsesTestResponse(body: incomplete)
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let agent = DevelopmentAgent(client: try VyronOutputLimitTestSupport.client(recorder: recorder),
                                     workspace: try workspace())
        do {
            _ = try await agent.run(
                goal: "Inspect this project.", model: VyronResponsesTestSupport.model,
                automaticModelSelection: false, onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("Repeated output exhaustion must remain an unfinished task")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .outputLimitReached)
        }
        let bodies = try await VyronOutputLimitTestSupport.generationBodies()
        XCTAssertEqual(bodies.count, 3)
        let events = await recorder.events
        XCTAssertEqual(events.count, 4, "One probe and three inference attempts have separate usage records")
        XCTAssertEqual(Set(events.map(\.requestID)).count, 4)
        for event in events.dropFirst() {
            guard case .measured = event.observation.result else { return XCTFail("Lost incomplete usage") }
        }
    }

    func testOutputContextAndEmptyFailuresShareOneRecoveryAllowance() async throws {
        let provider = VyronSteeringTestProvider { round, _ in
            if round == 1 { throw ModelProviderError.outputLimitReached }
            if round == 2 { throw DevelopmentAgentError.contextBudget }
            return DevelopmentMessage(role: "assistant", content: " \n\t")
        }
        do {
            _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
                goal: "Inspect the project.", model: "fixture-coder",
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("Mixed failures must not renew the inference recovery allowance")
        } catch {
            guard case .invalidTool(let detail) = error as? DevelopmentAgentError else {
                return XCTFail("Expected bounded unusable-response failure, received \(error)")
            }
            XCTAssertTrue(detail.contains("bounded recovery"))
        }
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 3)
    }

    func testCancellationDuringOutputRecoveryPreventsAnotherGeneration() async throws {
        let incomplete = try VyronOutputLimitTestSupport.incomplete()
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            return VyronResponsesTestResponse(body: incomplete)
        }
        let agent = DevelopmentAgent(client: try VyronResponsesTestSupport.client(), workspace: try workspace())
        let execution = Task {
            try await agent.run(
                goal: "Inspect the project.", model: VyronResponsesTestSupport.model,
                automaticModelSelection: false,
                onEvent: { event in
                    if event.content?.contains("max_output_tokens") == true {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                },
                approveCommand: { _ in false }
            )
        }
        do {
            _ = try await execution.value
            XCTFail("Cancellation must propagate")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let bodies = try await VyronOutputLimitTestSupport.generationBodies()
        XCTAssertEqual(bodies.count, 1)
    }

    func testNonLimitAndTransportFailuresDoNotEnterContentRecovery() async throws {
        let replies = [
            VyronResponsesTestResponse(body: try VyronOutputLimitTestSupport.incomplete(reason: "content_filter")),
            VyronResponsesTestResponse(body: try VyronOutputLimitTestSupport.incomplete(reason: "unknown")),
            VyronResponsesTestResponse(body: try VyronOutputLimitTestSupport.incomplete(reason: nil)),
            VyronResponsesTestResponse(body: "{malformed"),
            VyronResponsesTestResponse(body: "{}", statusCode: 500),
            VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([], status: "in_progress")),
            VyronResponsesTestResponse(body: """
            {"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},
             "error":{"code":"server_error"},"output":[]}
            """)
        ]
        for reply in replies {
            await VyronResponsesTestURLProtocol.state.reset { request, _ in
                if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
                return reply
            }
            let agent = DevelopmentAgent(client: try VyronResponsesTestSupport.client(), workspace: try workspace())
            do {
                _ = try await agent.run(
                    goal: "Inspect the project.", model: VyronResponsesTestSupport.model,
                    automaticModelSelection: false, onEvent: { _ in }, approveCommand: { _ in false }
                )
                XCTFail("Unclassified or transport failures must propagate")
            } catch {
                XCTAssertTrue(error is ModelProviderError)
                XCTAssertNotEqual(error as? ModelProviderError, .outputLimitReached)
            }
            let bodies = try await VyronOutputLimitTestSupport.generationBodies()
            XCTAssertEqual(bodies.count, 1)
        }
    }

    func testNewGuidanceDuringRecoveryPreventsAStaleWrite() async throws {
        let workspace = try workspace()
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Do not write files; describe the next steps.")
        let applied = VyronSteeringTestLog<UUID>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1:
                await inbox.append(update)
                throw ModelProviderError.outputLimitReached
            case 2:
                return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                    name: "write_file", arguments: ["path": .string("Stale.txt"), "content": .string("stale")]
                )])
            default:
                return DevelopmentMessage(role: "assistant", content: "Here are the next steps without file changes.")
            }
        }
        let result = try await DevelopmentAgent(client: provider, workspace: workspace).run(
            goal: "Create a project note.", model: "fixture-coder", steeringInbox: inbox,
            onSteeringApplied: { applied.append($0.id) }, onEvent: { _ in }, approveCommand: { _ in false }
        )
        XCTAssertTrue(result.changedFiles.isEmpty)
        let staleFile = workspace.rootURL.appendingPathComponent("Stale.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleFile.path))
        XCTAssertEqual(applied.values, [update.id])
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests[2].contains { $0.role == "user" && $0.content.contains(update.content) })
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronOpenAIOutputRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }

    private func externalTool() -> DevelopmentExternalTool {
        DevelopmentExternalTool(
            name: "mcp_fixture_create", description: "Create one fixture resource",
            inputSchema: ["type": .string("object")], isReadOnly: false
        )
    }
}
