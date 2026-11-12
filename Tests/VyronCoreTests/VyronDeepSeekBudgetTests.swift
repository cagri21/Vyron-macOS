import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronDeepSeekBudgetTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testPublishedOverridesApplyOnlyToDocumentedModelsOnTheOfficialEndpoint() throws {
        let settings = ModelSettings(contextTokens: 1_048_576, maxOutputTokens: 393_216)
        var profile = VyronDeepSeekTestSupport.profile(settings: settings)
        for model in ["deepseek-flash", "deepseek-v4-pro", "deepseek-v4-flash", "deepseek-v4-flash-vision-exp"] {
            profile.selectedModel = model
            XCTAssertEqual(try profile.validated().settings, settings, model)
        }

        profile.settings.contextTokens = 1_048_577
        XCTAssertThrowsError(try profile.validated())
        profile.settings = settings
        profile.settings.maxOutputTokens = 393_217
        XCTAssertThrowsError(try profile.validated())

        profile.settings = settings
        profile.selectedModel = "future-model"
        XCTAssertThrowsError(try profile.validated())
        profile.selectedModel = VyronDeepSeekTestSupport.model
        profile.endpoint = "https://models.example.test/v1"
        XCTAssertThrowsError(try profile.validated())
    }

    func testOfficialWorkKeepsLargeGuidanceAndFullEffortOutput() async throws {
        let guidance = String(repeating: "Follow the repository rules.\n", count: 1_500)
        let client = try VyronDeepSeekTestSupport.client(VyronDeepSeekTestSupport.profile())
        let budget = client.developmentMessageBudget(for: VyronDeepSeekTestSupport.model)
        XCTAssertEqual(budget.workingBytes, 98_304)
        XCTAssertEqual(budget.maximumBytes, 131_072)
        await stubCompletion()

        let result = try await client.developmentStep(
            model: VyronDeepSeekTestSupport.model,
            messages: [
                DevelopmentMessage(role: "system", content: guidance),
                DevelopmentMessage(role: "user", content: "Inspect this project.")
            ],
            effort: .ultra,
            mode: .plan
        )

        XCTAssertEqual(result.message.content, "Project inspected.")
        let body = try await onlyGenerationBody()
        XCTAssertEqual(body["max_tokens"] as? Int, AgentEffort.ultra.developmentBudget.outputTokens)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["content"] as? String, guidance)
    }

    func testPerRequestModelDoesNotInheritUnsupportedOverrides() async throws {
        let settings = ModelSettings(contextTokens: 1_048_576, maxOutputTokens: 393_216)
        let client = try VyronDeepSeekTestSupport.client(VyronDeepSeekTestSupport.profile(settings: settings))
        await stubCompletion()

        do {
            _ = try await client.developmentStep(
                model: "unknown-model",
                messages: [DevelopmentMessage(role: "user", content: "Inspect this project.")],
                mode: .plan
            )
            XCTFail("Expected the settings to be rejected for the requested model")
        } catch ModelProviderError.invalidSettings {
            let requests = await VyronResponsesTestURLProtocol.state.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testManualOutputReservationCompactsAnOlderToolExchange() async throws {
        let settings = ModelSettings(contextTokens: 32_768, maxOutputTokens: 16_384)
        let client = try VyronDeepSeekTestSupport.client(VyronDeepSeekTestSupport.profile(settings: settings))
        let oldCall = DevelopmentToolCall(name: "list_files", arguments: [:], id: "old")
        let currentCall = DevelopmentToolCall(name: "list_files", arguments: [:], id: "current")
        let oldResult = String(repeating: "old project result ", count: 1_000)
        await stubCompletion()

        let result = try await client.developmentStep(
            model: VyronDeepSeekTestSupport.model,
            messages: [
                DevelopmentMessage(role: "system", content: "Preserve project rules."),
                DevelopmentMessage(role: "user", content: "Inspect this project."),
                DevelopmentMessage(role: "assistant", toolCalls: [oldCall]),
                DevelopmentMessage(role: "tool", content: oldResult, toolName: "list_files", toolCallID: "old"),
                DevelopmentMessage(role: "user", content: "Include the current project state."),
                DevelopmentMessage(role: "assistant", toolCalls: [currentCall]),
                DevelopmentMessage(role: "tool", content: "README.md", toolName: "list_files", toolCallID: "current")
            ],
            effort: .quick,
            mode: .plan
        )

        XCTAssertEqual(result.message.content, "Project inspected.")
        let body = try await onlyGenerationBody()
        XCTAssertEqual(body["max_tokens"] as? Int, 16_384)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.compactMap { $0["role"] as? String }, ["system", "user", "user", "assistant", "tool"])
        XCTAssertEqual(messages.compactMap { $0["tool_call_id"] as? String }, ["current"])
        let assistant = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
        let calls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls.compactMap { $0["id"] as? String }, ["current"])
    }

    func testOfficialWorkRejectsGuidanceAboveTheHardByteLimitBeforeGeneration() async throws {
        let client = try VyronDeepSeekTestSupport.client(VyronDeepSeekTestSupport.profile())
        await stubCompletion()

        do {
            _ = try await client.developmentStep(
                model: VyronDeepSeekTestSupport.model,
                messages: [DevelopmentMessage(role: "user", content: String(repeating: "x", count: 131_073))],
                mode: .plan
            )
            XCTFail("Expected the local byte limit to reject this request")
        } catch {
            XCTAssertEqual(error as? DevelopmentAgentError, .contextBudget)
        }

        let requests = await VyronResponsesTestURLProtocol.state.requests
        XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/v1/models" })
    }

    private func stubCompletion() async {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            switch request.url?.path {
            case "/v1/models": try VyronDeepSeekTestSupport.models()
            case "/v1/chat/completions": try VyronDeepSeekTestSupport.completion(content: "Project inspected.")
            default: throw URLError(.unsupportedURL)
            }
        }
    }

    private func onlyGenerationBody() async throws -> [String: Any] {
        let requests = await VyronResponsesTestURLProtocol.state.requests
        let generation = requests.filter { $0.url?.path == "/v1/chat/completions" }
        XCTAssertEqual(generation.count, 1)
        return try VyronResponsesTestSupport.body(XCTUnwrap(generation.first))
    }
}
