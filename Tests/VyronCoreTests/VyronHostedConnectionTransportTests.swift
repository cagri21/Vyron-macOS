import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronHostedConnectionTransportTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testGeminiPresetDiscoversModelsAndStreamsChat() async throws {
        try await assertDiscoveryAndChat(
            profile: VyronGeminiConnectionPreset.makeProfile(),
            endpoint: "https://generativelanguage.googleapis.com/v1beta/openai",
            model: "gemini-3.8-flash"
        )
    }

    func testMetaPresetDiscoversModelsAndStreamsChat() async throws {
        try await assertDiscoveryAndChat(
            profile: VyronMetaConnectionPreset.makeProfile(),
            endpoint: "https://api.meta.ai/v1",
            model: "muse-spark-1.3"
        )
    }

    private func assertDiscoveryAndChat(
        profile: ModelConnectionProfile,
        endpoint: String,
        model: String
    ) async throws {
        let key = "offline-test-key"
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
            switch request.httpMethod {
            case "GET":
                XCTAssertEqual(request.url?.absoluteString, endpoint + "/models")
                return VyronResponsesTestResponse(body: #"{"data":[{"id":"\#(model)"}]}"#)
            case "POST":
                XCTAssertEqual(request.url?.absoluteString, endpoint + "/chat/completions")
                let body = try VyronResponsesTestSupport.body(request)
                XCTAssertEqual(body["model"] as? String, model)
                XCTAssertEqual(body["stream"] as? Bool, true)
                let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
                XCTAssertEqual(messages, [["role": "user", "content": "Hello"]])
                return VyronResponsesTestResponse(body: """
                data: {"choices":[{"delta":{"content":"Model "}}]}

                data: {"choices":[{"delta":{"content":"ready"},"finish_reason":"stop"}]}

                data: [DONE]


                """)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        XCTAssertTrue(try profile.makeProvider(apiKey: key) is OpenAICompatibleClient)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        let client = try OpenAICompatibleClient(connection: profile, apiKey: key, configuration: configuration)

        let models = try await client.models()
        XCTAssertEqual(models.map(\.name), [model])
        let answer = try await client.chat(
            model: profile.selectedModel,
            messages: [ChatMessage(role: "user", content: "Hello")]
        ) { _ in }
        XCTAssertEqual(answer, "Model ready")

        let requests = await VyronResponsesTestURLProtocol.state.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "POST"])
    }
}
