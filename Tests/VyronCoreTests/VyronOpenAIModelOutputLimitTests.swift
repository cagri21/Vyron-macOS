import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOpenAIModelOutputLimitTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testPublishedCeilingsCoverOfficialResponsesFamiliesAndOlderModels() {
        var profile = VyronOpenAIConnectionPreset.makeProfile()
        let reasoningModels = [
            "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-6.1-sol", "gpt-6.1-terra",
            "gpt-6.1-sol-2026-10-01", "gpt-6.2-astra", "gpt-6.2-sol", "gpt-6.2-sol-2026-11-18",
            "gpt-5.2", "gpt-5.6-sol"
        ]
        for model in reasoningModels {
            profile.selectedModel = model
            XCTAssertEqual(profile.publishedOutputTokenLimit, 128_000, model)
        }

        profile.selectedModel = "gpt-4.1"
        XCTAssertEqual(profile.publishedOutputTokenLimit, 32_768)
        profile.selectedModel = "gpt-4o"
        XCTAssertEqual(profile.publishedOutputTokenLimit, 16_384)
        profile.selectedModel = "gpt-4o-mini"
        XCTAssertEqual(profile.publishedOutputTokenLimit, 16_384)
    }

    func testPublishedCeilingDoesNotApplyToUnknownModelsOrOtherEndpoints() {
        var profile = VyronOpenAIConnectionPreset.makeProfile()
        profile.endpoint = " HTTPS://API.OPENAI.COM:443/v1/ "
        XCTAssertEqual(profile.publishedOutputTokenLimit, 128_000)
        profile.selectedModel = "gpt-6.1-sol-custom"
        XCTAssertNil(profile.publishedOutputTokenLimit)

        profile.selectedModel = "gpt-6.1-sol"
        for endpoint in [
            "https://api.openai.com.example.test/v1",
            "https://api.openai.com:8443/v1",
            "https://api.openai.com/proxy/v1",
            "https://api.openai.com/v1?mode=custom"
        ] {
            profile.endpoint = endpoint
            XCTAssertNil(profile.publishedOutputTokenLimit, endpoint)
        }
    }

    func testEditorAcceptsThePublishedResponsesCeilingAndRejectsOneTokenOver() throws {
        var profile = VyronOpenAIConnectionPreset.makeProfile()
        XCTAssertNil(try profile.validatedForEditing().settings.maxOutputTokens)
        profile.settings.maxOutputTokens = 128_000
        XCTAssertEqual(try profile.validatedForEditing().settings.maxOutputTokens, 128_000)
        profile.settings.maxOutputTokens = 128_001
        XCTAssertThrowsError(try profile.validatedForEditing())
    }

    func testLegacyGPT4oOverrideSurvivesStorageAndEditorRequiresAValidNewValue() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let store = ModelConnectionStore(fileURL: directory.appendingPathComponent("connections.json"))
        var legacy = VyronOpenAIConnectionPreset.makeProfile()
        legacy.selectedModel = "gpt-4o"
        legacy.settings.maxOutputTokens = 32_768
        let original = ModelConnectionState(profiles: [legacy], activeConnectionID: legacy.id)
        try JSONEncoder().encode(original).write(to: store.fileURL)

        let loaded = try store.load()
        XCTAssertEqual(loaded, original)
        try store.save(loaded)
        XCTAssertEqual(try store.load(), original)
        XCTAssertThrowsError(try legacy.validatedForEditing())
        legacy.settings.maxOutputTokens = 16_385
        XCTAssertThrowsError(try legacy.validatedForEditing())
        legacy.settings.maxOutputTokens = 16_384
        XCTAssertEqual(try legacy.validatedForEditing().settings.maxOutputTokens, 16_384)
    }

    func testResponsesChatSendsAnExplicitLargeBudgetAndKeepsAutomaticEffortBudget() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            XCTAssertEqual(request.url?.path, "/v1/responses")
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.stream("Done"))
        }
        let messages = [ChatMessage(role: "user", content: "Say done")]
        let model = VyronResponsesTestSupport.model
        for settings in [ModelSettings(), ModelSettings(maxOutputTokens: 50_000)] {
            let client = try VyronResponsesTestSupport.client(settings: settings)
            let reply = try await client.chat(model: model, messages: messages) { _ in }
            XCTAssertEqual(reply, "Done")
        }

        let requests = await VyronResponsesTestURLProtocol.state.requests
        let maximums = try requests.map { request in
            try XCTUnwrap(VyronResponsesTestSupport.body(request)["max_output_tokens"] as? Int)
        }
        XCTAssertEqual(maximums, [AgentEffort.automatic.developmentBudget.outputTokens, 50_000])
    }

    func testCompatibleChatClipsAnOlderGPT4oOverrideToThePublishedLimit() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(body["model"] as? String, "gpt-4o")
            XCTAssertEqual(body["max_tokens"] as? Int ?? body["max_completion_tokens"] as? Int, 16_384)
            return VyronResponsesTestResponse(body: """
            data: {"choices":[{"delta":{"content":"Done"},"finish_reason":"stop"}]}

            data: [DONE]


            """)
        }
        var profile = VyronOpenAIConnectionPreset.makeProfile()
        profile.selectedModel = "gpt-4o"
        profile.settings = ModelSettings(contextTokens: 65_536, maxOutputTokens: 32_768)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        let client = try OpenAICompatibleClient(connection: profile, configuration: configuration)
        let reply = try await client.chat(
            model: profile.selectedModel,
            messages: [ChatMessage(role: "user", content: "Say done")]
        ) { _ in }
        XCTAssertEqual(reply, "Done")
    }
}
