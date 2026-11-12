import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronDeepSeekTransportTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testReasoningAndNativeToolIDsReplayIncludingPriorFinalAnswers() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            XCTAssertEqual(request.url?.host, "api.deepseek.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer offline-deepseek-key")
            if request.url?.path == "/v1/models" { return try VyronDeepSeekTestSupport.models() }
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "enabled")
            XCTAssertEqual(body["reasoning_effort"] as? String, "high")
            XCTAssertNil(body["temperature"])
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let assistants = messages.filter { $0["role"] as? String == "assistant" }
            if messages.last?["content"] as? String == "A follow-up" {
                XCTAssertEqual(assistants.compactMap { $0["reasoning_content"] as? String }, [
                    "private-tool-reasoning", "private-final-reasoning"
                ])
                return try VyronDeepSeekTestSupport.completion(content: "Follow-up answer")
            }
            if messages.last?["role"] as? String == "tool" {
                XCTAssertEqual(messages.last?["tool_call_id"] as? String, "call-deepseek")
                XCTAssertEqual(assistants.last?["reasoning_content"] as? String, "private-tool-reasoning")
                let calls = try XCTUnwrap(assistants.last?["tool_calls"] as? [[String: Any]])
                XCTAssertEqual(calls.first?["id"] as? String, "call-deepseek")
                return try VyronDeepSeekTestSupport.completion(content: "Visible final")
            }
            return try VyronDeepSeekTestSupport.completion(
                content: "Inspecting files", reasoning: "private-tool-reasoning",
                calls: [VyronDeepSeekTestSupport.call()]
            )
        }
        let profile = VyronDeepSeekTestSupport.profile(settings: ModelSettings(temperature: 0.2))
        let client = try VyronDeepSeekTestSupport.client(profile)
        let base = [DevelopmentMessage(role: "user", content: "Inspect")]
        let first = try await client.developmentStep(
            model: VyronDeepSeekTestSupport.model, messages: base, mode: .plan
        )
        XCTAssertEqual(first.message.content, "Inspecting files")
        XCTAssertNotNil(first.message.continuation)
        let history = base + [first.message, DevelopmentMessage(
            role: "tool", content: "README.md", toolName: "list_files", toolCallID: "call-deepseek"
        )]
        let final = try await client.developmentStep(
            model: VyronDeepSeekTestSupport.model, messages: history, mode: .plan
        )
        XCTAssertEqual(final.message.content, "Visible final")
        XCTAssertNotNil(final.message.continuation)
        let restored = try JSONDecoder().decode(
            [DevelopmentMessage].self, from: JSONEncoder().encode(history + [final.message])
        )
        let followUp = try await client.developmentStep(
            model: VyronDeepSeekTestSupport.model,
            messages: restored + [DevelopmentMessage(role: "user", content: "A follow-up")], mode: .plan
        )
        XCTAssertEqual(followUp.message.content, "Follow-up answer")
    }

    func testChatStreamingHidesPrivateReasoningAndUsesEffortAndToggle() async throws {
        for effort in AgentEffort.allCases {
            let expected = VyronDeepSeekRequestConfiguration(settings: ModelSettings(), effort: effort).effort
            await VyronResponsesTestURLProtocol.state.reset { request, _ in
                let body = try VyronResponsesTestSupport.body(request)
                XCTAssertEqual(body["reasoning_effort"] as? String, expected)
                XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "enabled")
                XCTAssertNil(body["tools"])
                return VyronResponsesTestResponse(body: VyronDeepSeekTestSupport.stream(), fragmentBytes: 1)
            }
            let client = try VyronDeepSeekTestSupport.client(VyronDeepSeekTestSupport.profile())
            let output = try await client.chat(VyronChatInferenceRequest(
                model: VyronDeepSeekTestSupport.model,
                messages: [ChatMessage(role: "user", content: "Hi")],
                configuration: VyronChatInferenceConfiguration(systemPrompt: nil, effort: effort)
            )) { token in
                XCTAssertEqual(token, "Visible answer")
                XCTAssertFalse(token.contains("private"))
            }
            XCTAssertEqual(output, "Visible answer")
        }
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
            XCTAssertNil(body["reasoning_effort"])
            return VyronResponsesTestResponse(body: VyronDeepSeekTestSupport.stream())
        }
        let client = try VyronDeepSeekTestSupport.client(
            VyronDeepSeekTestSupport.profile(settings: ModelSettings(thinking: false))
        )
        _ = try await client.chat(
            model: VyronDeepSeekTestSupport.model, messages: [ChatMessage(role: "user", content: "Hi")]
        ) { _ in }
    }

    func testDataOnlyProbeAndRealNativePlanRunPreserveToolPermissions() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" {
                return VyronResponsesTestResponse(body: #"{"data":[{"id":"deepseek-flash"}]}"#)
            }
            let body = try VyronResponsesTestSupport.body(request)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            if body["tool_choice"] != nil {
                XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
                let prompt = try XCTUnwrap(messages.first?["content"] as? String)
                let range = try XCTUnwrap(prompt.range(of: "nonce "))
                let nonce = String(prompt[range.upperBound...].prefix(36))
                let arguments = try VyronResponsesTestSupport.json(["nonce": nonce])
                return try VyronDeepSeekTestSupport.completion(content: "", calls: [[
                    "id": "probe-call", "type": "function",
                    "function": ["name": "vyron_check_tools", "arguments": arguments]
                ]])
            }
            let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
            let names = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
            XCTAssertTrue(names.contains("list_files"))
            XCTAssertFalse(names.contains("write_file"))
            XCTAssertFalse(names.contains("run_command"))
            if messages.last?["role"] as? String == "tool" {
                let assistant = messages.last { $0["role"] as? String == "assistant" }
                XCTAssertEqual(assistant?["reasoning_content"] as? String, "private-plan-reasoning")
                return try VyronDeepSeekTestSupport.completion(content: "Project inspected.")
            }
            return try VyronDeepSeekTestSupport.completion(
                content: "", reasoning: "private-plan-reasoning", calls: [VyronDeepSeekTestSupport.call()]
            )
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let agent = DevelopmentAgent(
            client: try VyronDeepSeekTestSupport.client(VyronDeepSeekTestSupport.profile()),
            workspace: try DevelopmentWorkspace(rootURL: directory)
        )
        let result = try await agent.run(
            goal: "Inspect this project", model: VyronDeepSeekTestSupport.model,
            automaticModelSelection: false, effort: .balanced, mode: .plan,
            onEvent: { _ in }, approveCommand: { _ in XCTFail("Plan cannot execute commands"); return false }
        )
        XCTAssertEqual(result.finalMessage, "Project inspected.")
        XCTAssertTrue(result.changedFiles.isEmpty)
    }

    func testCancellationAndHTTPFailuresDoNotLeakReasoningOrCredentials() async throws {
        let started = expectation(description: "Streaming request started")
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            started.fulfill()
            return VyronResponsesTestResponse(body:
                "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"private-cancelled\"}}]}\n\n",
                holdOpen: true
            )
        }
        let client = try VyronDeepSeekTestSupport.client(VyronDeepSeekTestSupport.profile())
        let task = Task {
            try await client.chat(
                model: VyronDeepSeekTestSupport.model, messages: [ChatMessage(role: "user", content: "Hi")]
            ) { _ in XCTFail("Private reasoning cannot appear as a token") }
        }
        let readiness = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(readiness, .completed)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }

        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(body: "private-reasoning offline-deepseek-key", statusCode: 401)
        }
        do {
            _ = try await client.chat(
                model: VyronDeepSeekTestSupport.model, messages: [ChatMessage(role: "user", content: "Hi")]
            ) { _ in }
            XCTFail("Expected HTTP failure")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .http(401))
            XCTAssertFalse(error.localizedDescription.contains("private-reasoning"))
            XCTAssertFalse(error.localizedDescription.contains("offline-deepseek-key"))
        }
    }
}
