import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronHostedOutputLimitTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testPublishedCeilingsForHostedPresetsAndVariants() {
        var gemini = VyronGeminiConnectionPreset.makeProfile()
        XCTAssertEqual(gemini.publishedOutputTokenLimit, 65_536)
        gemini.selectedModel = "gemini-3.1-flash-lite"
        XCTAssertEqual(gemini.publishedOutputTokenLimit, 65_536)

        var meta = VyronMetaConnectionPreset.makeProfile()
        XCTAssertEqual(meta.publishedOutputTokenLimit, 131_072)
        meta.selectedModel = "muse-ember-1.0"
        XCTAssertEqual(meta.publishedOutputTokenLimit, 524_288)

        var claude = VyronClaudeConnectionPreset.makeProfile()
        XCTAssertEqual(claude.publishedOutputTokenLimit, 128_000)
        claude.selectedModel = "claude-sonnet-4-5-20250929"
        XCTAssertEqual(claude.publishedOutputTokenLimit, 64_000)
        claude.selectedModel = "claude-unknown"
        XCTAssertNil(claude.publishedOutputTokenLimit)
    }

    func testCompatibleCeilingsAreScopedToExactPublishedModelsAndOfficialEndpoints() {
        var gemini = VyronGeminiConnectionPreset.makeProfile()
        gemini.settings.maxOutputTokens = 50_000
        var unknown = gemini
        unknown.selectedModel = "gemini-3.8-flash-unknown"
        XCTAssertNil(unknown.publishedOutputTokenLimit)
        XCTAssertThrowsError(try unknown.validated())

        gemini.endpoint = "https://generativelanguage.googleapis.com.example.test/v1beta/openai"
        XCTAssertNil(gemini.publishedOutputTokenLimit)
        XCTAssertThrowsError(try gemini.validated())

        var meta = VyronMetaConnectionPreset.makeProfile()
        meta.selectedModel = "muse-spark-1.3-unknown"
        XCTAssertNil(meta.publishedOutputTokenLimit)
        meta.selectedModel = VyronMetaConnectionPreset.defaultModel
        meta.endpoint = "https://models.example.test/v1"
        meta.settings.maxOutputTokens = 50_000
        XCTAssertNil(meta.publishedOutputTokenLimit)
        XCTAssertThrowsError(try meta.validated())
    }

    func testManualPublishedCeilingsRoundTripAndRejectOneTokenOver() throws {
        for preset in [
            VyronGeminiConnectionPreset.makeProfile(),
            VyronMetaConnectionPreset.makeProfile(),
            VyronClaudeConnectionPreset.makeProfile()
        ] {
            let ceiling = try XCTUnwrap(preset.publishedOutputTokenLimit)
            var profile = preset
            profile.settings.maxOutputTokens = ceiling
            let validated = try profile.validated()
            let encoded = try JSONEncoder().encode(validated)
            let restored = try JSONDecoder().decode(ModelConnectionProfile.self, from: encoded)
            XCTAssertEqual(try restored.validated(), validated)
            XCTAssertEqual(restored.id, preset.id)
            XCTAssertEqual(restored.settings.maxOutputTokens, ceiling)

            profile.settings.maxOutputTokens = ceiling + 1
            XCTAssertThrowsError(try profile.validated())
        }
    }

    func testCompatibleChatSendsManualLargeBudgetsAndKeepsAutomaticEffortBudget() async throws {
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(body: """
            data: {"choices":[{"delta":{"content":"Done"},"finish_reason":"stop"}]}

            data: [DONE]


            """)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        let presets = [
            VyronGeminiConnectionPreset.makeProfile(),
            VyronMetaConnectionPreset.makeProfile()
        ]
        for preset in presets {
            var manual = preset
            manual.settings = ModelSettings(contextTokens: 65_536, maxOutputTokens: 50_000)
            for profile in [preset, manual] {
                let client = try OpenAICompatibleClient(connection: profile, configuration: configuration)
                let response = try await client.chat(
                    model: profile.selectedModel,
                    messages: [ChatMessage(role: "user", content: "Say done")]
                ) { _ in }
                XCTAssertEqual(response, "Done")
            }
        }

        let requests = await VyronResponsesTestURLProtocol.state.requests
        let budgets = try requests.map { request in
            let body = try VyronResponsesTestSupport.body(request)
            return try XCTUnwrap(body["max_tokens"] as? Int ?? body["max_completion_tokens"] as? Int)
        }
        let automatic = AgentEffort.automatic.developmentBudget.outputTokens
        XCTAssertEqual(budgets, [automatic, 50_000, automatic, 50_000])
    }
}
