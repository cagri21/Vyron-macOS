import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOpenAIModelFeatureTests: XCTestCase {
    override func tearDown() {
        VyronCompatibleFeatureTestURLProtocol.state.reset()
        super.tearDown()
    }

    func testKnownHostedDeepSeekSelectionsRejectDevelopmentBeforeAnyRequest() async throws {
        VyronCompatibleFeatureTestURLProtocol.state.reset()

        for model in ["deepseek-flash", "deepseek-v4-pro", "deepseek-reasoner"] {
            let client = try client(model: model)
            do {
                _ = try await client.developmentModel(
                    model: model, automaticModelSelection: false, effort: .balanced
                )
                XCTFail("Expected unsupported native tools for \(model)")
            } catch {
                XCTAssertEqual(error as? ModelProviderError, .unsupportedTools)
            }
        }

        XCTAssertEqual(VyronCompatibleFeatureTestURLProtocol.state.requestCount, 0)
    }

    func testAutomaticallyDiscoveredHostedDeepSeekRejectsBeforeToolProbe() async throws {
        let model = "deepseek-flash"
        configureDiscovery(model: model)
        let client = try client(model: model)

        do {
            _ = try await client.developmentModel(model: "", automaticModelSelection: true, effort: .quick)
            XCTFail("Expected the discovered model to reject native tools")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .unsupportedTools)
        }

        XCTAssertEqual(VyronCompatibleFeatureTestURLProtocol.state.requestCount, 1)
    }

    func testHostedDeepSeekChatStillStreamsWithoutToolFields() async throws {
        VyronCompatibleFeatureTestURLProtocol.state.reset { request in
            XCTAssertEqual(request.url?.host, "api.deepseek.com")
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let body = try Self.requestBody(request)
            XCTAssertEqual(body["model"] as? String, "deepseek-flash")
            XCTAssertEqual(body["stream"] as? Bool, true)
            XCTAssertNil(body["tools"])
            XCTAssertNil(body["tool_choice"])
            return """
            data: {"choices":[{"delta":{"content":"Chat ready"},"finish_reason":"stop"}]}

            data: [DONE]


            """
        }
        let client = try client(model: "deepseek-flash")

        let answer = try await client.chat(
            model: "deepseek-flash",
            messages: [ChatMessage(role: "user", content: "Hello")]
        ) { _ in }

        XCTAssertEqual(answer, "Chat ready")
        XCTAssertEqual(VyronCompatibleFeatureTestURLProtocol.state.requestCount, 1)
    }

    func testUnknownDeepSeekModelIDRemainsEligibleForNativeTools() async throws {
        try await assertDiscoveryAllows(model: "future-model", endpoint: "https://api.deepseek.com/v1")
    }

    func testDeepSeekModelIDOnAnotherHostRemainsEligibleForNativeTools() async throws {
        try await assertDiscoveryAllows(model: "deepseek-flash", endpoint: "https://models.example.test/v1")
    }

    private func client(
        model: String,
        endpoint: String = "https://api.deepseek.com/v1"
    ) throws -> OpenAICompatibleClient {
        let profile = ModelConnectionProfile(
            name: "Offline feature test",
            kind: .openAICompatible,
            endpoint: endpoint,
            selectedModel: model
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronCompatibleFeatureTestURLProtocol.self]
        return try OpenAICompatibleClient(connection: profile, configuration: configuration)
    }

    private func configureDiscovery(model: String) {
        VyronCompatibleFeatureTestURLProtocol.state.reset { request in
            XCTAssertEqual(request.url?.path, "/v1/models", "No tool probe should be sent")
            let body: [String: Any] = ["data": [["id": model, "capabilities": ["tools"]]]]
            return String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        }
    }

    private func assertDiscoveryAllows(model: String, endpoint: String) async throws {
        configureDiscovery(model: model)
        let client = try client(model: model, endpoint: endpoint)

        let selected = try await client.developmentModel(
            model: model, automaticModelSelection: false, effort: .balanced
        )

        XCTAssertEqual(selected.name, model)
        XCTAssertEqual(selected.capabilities, ["tools"])
        XCTAssertEqual(VyronCompatibleFeatureTestURLProtocol.state.requestCount, 1)
    }

    nonisolated private static func requestBody(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotDecodeRawData)
        }
        return body
    }
}
