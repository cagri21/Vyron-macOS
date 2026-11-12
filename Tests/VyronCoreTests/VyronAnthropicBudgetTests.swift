import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronAnthropicBudgetTests: XCTestCase {
    private nonisolated static let model = "claude-opus-4-7"
    private nonisolated static let key = "offline-anthropic-test-key"
    private nonisolated static let messagesPath = "/v1/messages"
    private nonisolated static let countPath = "/v1/messages/count_tokens"
    private let largeGuidance = String(repeating: "Retain this project guidance.\n", count: 1_400)

    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testClaudeLimitsRecognizeCurrentAndDatedLegacyModelIDs() {
        XCTAssertEqual(VyronClaudeModelBudget.contextTokens(for: Self.model), 1_000_000)
        XCTAssertEqual(VyronClaudeModelBudget.maximumOutputTokens(for: Self.model), 128_000)
        XCTAssertEqual(VyronClaudeModelBudget.contextTokens(for: "claude-sonnet-4-6"), 1_000_000)
        XCTAssertEqual(VyronClaudeModelBudget.maximumOutputTokens(for: "claude-sonnet-4-6"), 128_000)
        XCTAssertEqual(VyronClaudeModelBudget.contextTokens(for: "claude-sonnet-4-5-20250929"), 200_000)
        XCTAssertEqual(VyronClaudeModelBudget.maximumOutputTokens(for: "claude-sonnet-4-5-20250929"), 64_000)
    }

    func testManualClaudeLimitsRoundTripWithTheSameConnectionIdentity() throws {
        let settings = ModelSettings(contextTokens: 1_000_000, maxOutputTokens: 128_000)
        let saved = try profile(settings: settings).validated()
        let data = try JSONEncoder().encode(saved)
        let restored = try JSONDecoder().decode(ModelConnectionProfile.self, from: data)

        XCTAssertEqual(try restored.validated(), saved)
        XCTAssertEqual(restored.settings, settings)
        var tooMuchOutput = restored
        tooMuchOutput.settings.maxOutputTokens = 128_001
        XCTAssertThrowsError(try tooMuchOutput.validated())
    }

    func testOrdinaryRequestUsesSavedOutputWithoutCounting() async throws {
        await stub(countResponse: nil)

        let result = try await step(using: client(), guidance: "Follow the project rules.")

        XCTAssertEqual(result.message.content, "Finished.")
        let requests = try await budgetRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, [Self.messagesPath])
        let generation = try VyronResponsesTestSupport.body(XCTUnwrap(requests.first))
        XCTAssertEqual(generation["max_tokens"] as? Int, 4_096)
    }

    func testHighManualOutputUsesStreamingWithoutCountingAnOrdinaryRequest() async throws {
        await stub(countResponse: nil)
        let provider = try client(settings: ModelSettings(maxOutputTokens: 128_000))

        let result = try await step(using: provider, guidance: "Follow the project rules.")

        XCTAssertEqual(result.message.content, "Finished.")
        let requests = try await budgetRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, [Self.messagesPath])
        let generation = try VyronResponsesTestSupport.body(XCTUnwrap(requests.first))
        XCTAssertEqual(generation["max_tokens"] as? Int, 128_000)
        XCTAssertEqual(generation["stream"] as? Bool, true)
    }

    func testExactCountKeepsTheSameSystemMessagesAndSchemasAndReservesSavedOutput() async throws {
        await stub(countResponse: .init(body: #"{"input_tokens":8000}"#))

        let result = try await step(using: client(), guidance: largeGuidance)

        XCTAssertEqual(result.message.content, "Finished.")
        let requests = try await budgetRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, [Self.countPath, Self.messagesPath])
        let countRequest = try XCTUnwrap(requests.first)
        let generationRequest = try XCTUnwrap(requests.last)
        let count = try VyronResponsesTestSupport.body(countRequest)
        let generation = try VyronResponsesTestSupport.body(generationRequest)
        XCTAssertNil(count["max_tokens"])
        XCTAssertNil(count["stream"])
        XCTAssertEqual(generation["max_tokens"] as? Int, 4_096)
        XCTAssertEqual(count["model"] as? String, Self.model)
        for key in ["model", "system", "messages", "tools"] {
            XCTAssertEqual(
                try VyronResponsesTestSupport.json([XCTUnwrap(count[key])]),
                try VyronResponsesTestSupport.json([XCTUnwrap(generation[key])])
            )
        }
        XCTAssertTrue(try VyronResponsesTestSupport.json([XCTUnwrap(count["system"])]).contains("Retain this project"))
        let messages = try XCTUnwrap(count["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.compactMap { $0["role"] as? String }, ["user", "assistant", "user"])
        let assistant = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
        let toolUse = try XCTUnwrap((assistant["content"] as? [[String: Any]])?.last)
        XCTAssertEqual(toolUse["type"] as? String, "tool_use")
        XCTAssertEqual(toolUse["id"] as? String, "toolu_reference")
        let resultMessage = try XCTUnwrap(messages.last { $0["role"] as? String == "user" })
        let toolResult = try XCTUnwrap((resultMessage["content"] as? [[String: Any]])?.first)
        XCTAssertEqual(toolResult["type"] as? String, "tool_result")
        XCTAssertEqual(toolResult["tool_use_id"] as? String, "toolu_reference")
        let tools = try XCTUnwrap(count["tools"] as? [[String: Any]])
        let fixture = try XCTUnwrap(tools.first { $0["name"] as? String == "project_reference" })
        XCTAssertEqual((fixture["input_schema"] as? [String: String])?["type"], "object")
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), Self.key)
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        }
    }

    func testCountCannotSpendReservedOutputOrAuthorizeGenerationWithInvalidData() async throws {
        let fixtures = [
            #"{"input_tokens":28600}"#,
            #"{"input_tokens":30000}"#,
            #"{"input_tokens":-1}"#,
            #"{"input_tokens":true}"#,
            #"{"input_tokens":1.5}"#,
            "{}",
            "{malformed"
        ]
        for fixture in fixtures {
            await stub(countResponse: .init(body: fixture))
            do {
                _ = try await step(using: client(), guidance: largeGuidance)
                XCTFail("Invalid or oversized token count authorized generation: \(fixture)")
            } catch {
                XCTAssertTrue(error is ModelProviderError || error as? DevelopmentAgentError == .contextBudget)
            }
            let requests = try await budgetRequests()
            XCTAssertEqual(requests.map { $0.url?.path }, [Self.countPath])
        }
    }

    func testHTTPCountFailureDoesNotGenerate() async throws {
        await stub(countResponse: .init(body: "private error detail", statusCode: 503))

        do {
            _ = try await step(using: client(), guidance: largeGuidance)
            XCTFail("An HTTP count failure authorized generation")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .http(503))
        }
        let requests = try await budgetRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, [Self.countPath])
    }

    func testAuthoritativeMessagesOverTheByteLimitAreNeverSentToTheCounter() async throws {
        await stub(countResponse: nil)

        do {
            _ = try await step(using: client(), guidance: String(repeating: "x", count: 131_072))
            XCTFail("Oversized messages reached generation")
        } catch {
            XCTAssertEqual(error as? DevelopmentAgentError, .contextBudget)
        }
        let requests = try await budgetRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testCancellingCountDoesNotStartGeneration() async throws {
        await stub(countResponse: .init(body: "{", holdOpen: true))
        let provider = try client()
        let operation = Task { try await step(using: provider, guidance: largeGuidance) }
        for _ in 0..<1_000 {
            let requests = await VyronResponsesTestURLProtocol.state.requests
            if requests.contains(where: { $0.url?.path == Self.countPath }) { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        operation.cancel()

        do {
            _ = try await operation.value
            XCTFail("Cancellation did not propagate")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let requests = try await budgetRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, [Self.countPath])
    }

    private func client(
        settings: ModelSettings = ModelSettings(contextTokens: 32_768, maxOutputTokens: 4_096)
    ) throws -> VyronAnthropicClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        return try VyronAnthropicClient(
            connection: profile(settings: settings),
            apiKey: Self.key,
            configuration: configuration
        )
    }

    private func profile(settings: ModelSettings) -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Offline Anthropic test",
            kind: .anthropic,
            endpoint: "https://api.anthropic.com/v1",
            selectedModel: Self.model,
            settings: settings
        )
    }

    private func step(using client: VyronAnthropicClient, guidance: String) async throws -> DevelopmentStep {
        let call = DevelopmentToolCall(name: "project_reference", arguments: [:], id: "toolu_reference")
        return try await client.developmentStep(
            model: Self.model,
            messages: [
                DevelopmentMessage(role: "system", content: guidance),
                DevelopmentMessage(role: "user", content: "Inspect this project."),
                DevelopmentMessage(role: "assistant", toolCalls: [call]),
                DevelopmentMessage(
                    role: "tool",
                    content: "The project reference.",
                    toolName: call.function.name,
                    toolCallID: call.id
                )
            ],
            effort: .balanced,
            mode: .plan,
            externalTools: [DevelopmentExternalTool(
                name: "project_reference",
                description: "Look up a project reference.",
                inputSchema: ["type": .string("object")],
                isReadOnly: true
            )]
        )
    }

    private func budgetRequests() async throws -> [URLRequest] {
        try await VyronResponsesTestURLProtocol.state.requests.filter { request in
            guard request.url?.path != "/v1/models" else { return false }
            return try !Self.isToolProbe(VyronResponsesTestSupport.body(request))
        }
    }

    private func stub(countResponse: VyronResponsesTestResponse?) async {
        await VyronResponsesTestURLProtocol.state.reset({ request, _ in
            switch request.url?.path {
            case "/v1/models": return try Self.modelList()
            case Self.countPath: return try XCTUnwrap(countResponse)
            case Self.messagesPath: return try Self.messageResponse(for: request)
            default: throw URLError(.unsupportedURL)
            }
        }, automaticallyAnswerToolProbe: false)
    }

    private nonisolated static func isToolProbe(_ body: [String: Any]) -> Bool {
        (body["tools"] as? [[String: Any]])?.contains { $0["name"] as? String == "vyron_check_tools" } == true
    }

    private nonisolated static func modelList() throws -> VyronResponsesTestResponse {
        VyronResponsesTestResponse(body: try VyronResponsesTestSupport.json([
            "data": [[
                "id": model,
                "type": "model",
                "display_name": "Claude Opus 4.7",
                "created_at": "2026-04-01T00:00:00Z"
            ]],
            "first_id": model,
            "last_id": model,
            "has_more": false
        ]))
    }

    private nonisolated static func messageResponse(for request: URLRequest) throws -> VyronResponsesTestResponse {
        let body = try VyronResponsesTestSupport.body(request)
        let isProbe = isToolProbe(body)
        if !isProbe, body["stream"] as? Bool == true { return try messageStream() }
        let content: [String: Any]
        if isProbe {
            let prompt = try VyronResponsesTestSupport.json(XCTUnwrap(body["messages"]))
            let range = try XCTUnwrap(prompt.range(of: "nonce "))
            let nonce = String(prompt[range.upperBound...].prefix(36))
            XCTAssertNotNil(UUID(uuidString: nonce))
            content = ["type": "tool_use", "id": "toolu_test", "name": "vyron_check_tools", "input": ["nonce": nonce]]
        } else {
            content = ["type": "text", "text": "Finished."]
        }
        return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.json([
            "id": "msg_test",
            "model": model,
            "type": "message",
            "role": "assistant",
            "content": [content],
            "stop_reason": isProbe ? "tool_use" : "end_turn",
            "stop_sequence": NSNull(),
            "usage": ["input_tokens": 8, "output_tokens": 4]
        ]))
    }

    private nonisolated static func messageStream() throws -> VyronResponsesTestResponse {
        let events: [[String: Any]] = [
            ["type": "message_start", "message": [
                "id": "msg_test", "model": model, "type": "message", "role": "assistant", "content": [],
                "stop_reason": NSNull(), "stop_sequence": NSNull(), "usage": ["input_tokens": 8, "output_tokens": 0]
            ]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "Finished."]],
            ["type": "content_block_stop", "index": 0],
            ["type": "message_delta", "delta": ["stop_reason": "end_turn", "stop_sequence": NSNull()],
             "usage": ["output_tokens": 4]],
            ["type": "message_stop"]
        ]
        let body = try events.map { event in
            let kind = try XCTUnwrap(event["type"] as? String)
            return "event: \(kind)\ndata: \(try VyronResponsesTestSupport.json(event))\n\n"
        }.joined()
        return VyronResponsesTestResponse(body: body)
    }
}
