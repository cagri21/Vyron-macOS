import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronAutoLocalReasoningTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testKnownOfficialFamiliesUseOnlyCommonLevelsWhenOptedIn() {
        for model in [
            "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-6.1-sol", "gpt-6.1-terra",
            "gpt-6.2-astra", "gpt-6.2-sol", "gpt-6.2-sol-2026-11-18"
        ] {
            XCTAssertEqual(VyronOpenAIAutomaticReasoning.effort(for: model, effort: .quick, enabled: true), "low")
            XCTAssertEqual(VyronOpenAIAutomaticReasoning.effort(for: model, effort: .balanced, enabled: true), "medium")
            for effort in [AgentEffort.deep, .extraHigh, .maximum, .ultra] {
                XCTAssertEqual(VyronOpenAIAutomaticReasoning.effort(for: model, effort: effort, enabled: true), "high")
            }
            XCTAssertNil(VyronOpenAIAutomaticReasoning.effort(for: model, effort: .automatic, enabled: true))
            XCTAssertNil(VyronOpenAIAutomaticReasoning.effort(for: model, effort: .deep, enabled: false))
        }
        for model in ["gpt-5.5", "gpt-6.2-sol-proxy", "gpt-6.2-sol-2026-11-18-extra", "unknown"] {
            XCTAssertNil(VyronOpenAIAutomaticReasoning.effort(for: model, effort: .deep, enabled: true))
        }
    }

    func testChatUsesAssessedEffortAndKeepsManualSelectionsAtProviderDefaults() async throws {
        for enabled in [false, true] {
            for effort in [AgentEffort.quick, .balanced, .deep] {
                let expected = enabled
                    ? VyronOpenAIAutomaticReasoning.effort(
                        for: VyronResponsesTestSupport.model, effort: effort, enabled: true
                    ) : nil
                await VyronResponsesTestURLProtocol.state.reset { request, _ in
                    let body = try VyronResponsesTestSupport.body(request)
                    XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], expected)
                    XCTAssertEqual(body["stream"] as? Bool, true)
                    return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.stream("Ready."))
                }
                let client = try client(automaticReasoning: enabled)
                let answer = try await VyronChatInference.response(
                    using: client,
                    request: VyronChatInferenceRequest(
                        model: VyronResponsesTestSupport.model,
                        messages: [ChatMessage(role: .user, content: "Explain the result")],
                        configuration: VyronChatInferenceConfiguration(systemPrompt: nil, effort: effort)
                    ),
                    onToken: { _ in }
                )
                XCTAssertEqual(answer, "Ready.")
            }
        }
    }

    func testWorkAppliesAssessedReasoningAndPreservesSavedOutputBudget() async throws {
        let profile = VyronResponsesTestSupport.profile(settings: ModelSettings(maxOutputTokens: 4_096))
        for effort in [AgentEffort.quick, .balanced, .deep] {
            let expected = VyronOpenAIAutomaticReasoning.effort(
                for: profile.selectedModel, effort: effort, enabled: true
            )
            await VyronResponsesTestURLProtocol.state.reset { request, _ in
                if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
                let body = try VyronResponsesTestSupport.body(request)
                XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], expected)
                XCTAssertEqual(body["max_output_tokens"] as? Int, 4_096)
                XCTAssertEqual(body["stream"] as? Bool, false)
                XCTAssertEqual(body["include"] as? [String], ["reasoning.encrypted_content"])
                return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                    VyronResponsesTestSupport.reasoning(), VyronResponsesTestSupport.textOutput("Plan ready.")
                ]))
            }
            let client = try client(automaticReasoning: true, profile: profile)
            let step = try await client.developmentStep(
                model: profile.selectedModel,
                messages: [DevelopmentMessage(role: "user", content: "Plan this fix")],
                effort: effort,
                mode: .plan
            )
            XCTAssertEqual(step.message.content, "Plan ready.")
            XCTAssertFalse(step.message.content.contains("opaque-"))
        }
    }

    func testCandidateReasoningSupportMatchesOnlyOfficialRoutes() {
        let official = VyronResponsesTestSupport.profile()
        XCTAssertEqual(
            VyronAutoLocalProviderCapabilities.thinkingSupport(for: official),
            .levels(VyronModelThinkingLevels(levels: [.low, .medium, .high]))
        )
        var proxy = official
        proxy.endpoint = "https://api.openai.com.example.test/v1"
        XCTAssertEqual(VyronAutoLocalProviderCapabilities.thinkingSupport(for: proxy), .providerDefaultOnly)
        var deepSeek = official
        deepSeek.endpoint = VyronDeepSeekRoute.endpoint
        deepSeek.selectedModel = VyronDeepSeekRoute.defaultModel
        XCTAssertEqual(VyronAutoLocalProviderCapabilities.thinkingSupport(for: deepSeek), .boolean)
        deepSeek.selectedModel = "unknown-model"
        XCTAssertEqual(VyronAutoLocalProviderCapabilities.thinkingSupport(for: deepSeek), .unverified)
        deepSeek.kind = .ollama
        XCTAssertEqual(VyronAutoLocalProviderCapabilities.thinkingSupport(for: deepSeek), .unverified)
    }

    func testSavedProfileAloneDoesNotClaimImageSupport() {
        var profile = VyronResponsesTestSupport.profile()
        for kind in [ModelProviderKind.openAICompatible, .anthropic, .ollama] {
            profile.kind = kind
            XCTAssertFalse(VyronAutoLocalProviderCapabilities.supportsImages(for: profile))
        }
    }

    func testUnknownModelKeepsReasoningOmittedEvenWithAutoLocalEnabled() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertNil(body["reasoning"])
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.stream("Ready."))
        }
        _ = try await VyronChatInference.response(
            using: client(automaticReasoning: true),
            request: VyronChatInferenceRequest(
                model: "unknown-model",
                messages: [ChatMessage(role: .user, content: "Analyze")],
                configuration: VyronChatInferenceConfiguration(systemPrompt: nil, effort: .deep)
            ),
            onToken: { _ in }
        )
    }

    private func client(
        automaticReasoning: Bool,
        profile: ModelConnectionProfile = VyronResponsesTestSupport.profile()
    ) throws -> VyronOpenAIResponsesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        return try VyronOpenAIResponsesClient(
            connection: profile,
            apiKey: "offline-test-key",
            transport: .init(configuration: configuration, automaticReasoning: automaticReasoning)
        )
    }
}
