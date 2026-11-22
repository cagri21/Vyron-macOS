import Foundation
import XCTest
import VyronModelDomain
@testable import VyronModelData

@MainActor
final class VyronOllamaNativeToolCheckTests: XCTestCase {
    override func tearDown() {
        VyronDevelopmentBudgetURLProtocol.state.configure(nil)
        super.tearDown()
    }

    func testNativeNonceIsRequiredEvenWhenTheImportedModelAdvertisesTools() async throws {
        configure(native: false)
        let client = try client()
        do {
            try await client.requireNativeToolSupport(for: imported)
            XCTFail("Printed tool JSON is not native function transport.")
        } catch let error as ModelProviderError {
            XCTAssertEqual(error, .unsupportedTools)
        }
        let requests = VyronDevelopmentBudgetURLProtocol.state.requests.filter { $0.url?.path == "/api/chat" }
        XCTAssertEqual(requests.count, 1)
        let body = try Self.fields(XCTUnwrap(requests.first))
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }, ["vyron_check_tools"])
        XCTAssertEqual(body["think"] as? Bool, false)
    }

    func testSuccessfulProofIsSeparateFromMetadataAndKeyedByTheCurrentWeightDigest() async throws {
        configure(digest: "weights-one", native: true)
        let client = try client()
        try await client.requireNativeToolSupport(for: imported)
        try await client.requireNativeToolSupport(for: imported)
        XCTAssertEqual(VyronDevelopmentBudgetURLProtocol.state.requests.filter { $0.url?.path == "/api/chat" }.count, 1)
        configure(digest: "weights-two", native: true)
        try await client.requireNativeToolSupport(for: imported)
        XCTAssertEqual(VyronDevelopmentBudgetURLProtocol.state.requests.filter { $0.url?.path == "/api/chat" }.count, 1)
    }

    func testWrongNonceCannotMarkNativeToolsVerified() async throws {
        configure(native: true, matchingNonce: false)
        do {
            try await client().requireNativeToolSupport(for: imported)
            XCTFail("A mismatched native response is not proof for this request.")
        } catch let error as ModelProviderError {
            XCTAssertEqual(error, .unsupportedTools)
        }
    }

    func testCuratedCodingAndExplicitlyUnsupportedModelsKeepTheirExistingContracts() async throws {
        let client = try client()
        try await client.requireNativeToolSupport(for: .init(name: "qwen3-coder:30b", size: 19_000_000_000))
        XCTAssertTrue(VyronDevelopmentBudgetURLProtocol.state.requests.isEmpty)
        do {
            try await client.requireNativeToolSupport(for: .init(name: "custom-chat:latest", size: 1, capabilities: ["completion"]))
            XCTFail("A model without advertised tools must not reach a probe.")
        } catch let error as ModelProviderError {
            XCTAssertEqual(error, .unsupportedTools)
        }
        XCTAssertTrue(VyronDevelopmentBudgetURLProtocol.state.requests.isEmpty)
    }

    private var imported: LocalModel {
        .init(name: "imported-reasoner:8b", size: 8_000_000_000, capabilities: ["completion", "tools", "thinking"])
    }

    private func client() throws -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronDevelopmentBudgetURLProtocol.self]
        return try OllamaClient(settings: .init(contextTokens: 131_072), configuration: configuration)
    }

    private func configure(digest: String = "weights-one", native: Bool, matchingNonce: Bool = true) {
        VyronDevelopmentBudgetURLProtocol.state.configure { request in
            switch request.url?.path {
            case "/api/tags":
                return try JSONSerialization.data(withJSONObject: ["models": [[
                    "name": "imported-reasoner:8b", "size": 8_000_000_000, "digest": digest,
                    "capabilities": ["completion", "tools", "thinking"]
                ]]])
            case "/api/show":
                return Data(#"{"capabilities":["completion","tools","thinking"],"thinking":{"values":[false,true]},"model_info":{"fixture.context_length":262144}}"#.utf8)
            case "/api/chat":
                let body = try Self.fields(request)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                let prompt = try XCTUnwrap(messages.first?["content"] as? String)
                let range = try XCTUnwrap(prompt.range(of: "nonce "))
                let nonce = String(prompt[range.upperBound...].prefix(36))
                if native {
                    return try JSONSerialization.data(withJSONObject: ["done": true, "message": [
                        "role": "assistant", "content": "", "tool_calls": [["function": [
                            "name": "vyron_check_tools", "arguments": ["nonce": matchingNonce ? nonce : "wrong"]
                        ]]]
                    ]])
                }
                return try JSONSerialization.data(withJSONObject: ["done": true, "message": [
                    "role": "assistant", "content": "```json\n{\"tool\":\"vyron_check_tools\",\"nonce\":\"\(nonce)\"}\n```"
                ]])
            default: throw URLError(.unsupportedURL)
            }
        }
    }

    nonisolated private static func fields(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream, data.isEmpty {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
