import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

private final class ProviderStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (Int, String))?
    func set(_ handler: (@Sendable (URLRequest) throws -> (Int, String))?) { lock.withLock { self.handler = handler } }
    func handle(_ request: URLRequest) throws -> (Int, String) {
        guard let handler = lock.withLock({ handler }) else { throw URLError(.unsupportedURL) }
        return try handler(request)
    }
}

private final class ProviderURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = ProviderStubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.state.handle(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let bytes = Data(body.utf8)
            let midpoint = bytes.count / 2
            client?.urlProtocol(self, didLoad: Data(bytes.prefix(midpoint)))
            client?.urlProtocol(self, didLoad: Data(bytes.dropFirst(midpoint)))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func providerBody(_ request: URLRequest) throws -> [String: Any] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
    }
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}

final class ModelProviderTests: XCTestCase, @unchecked Sendable {
    override func tearDown() { ProviderURLProtocol.state.set(nil); super.tearDown() }

    private func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProviderURLProtocol.self]
        return config
    }

    private func profile(kind: ModelProviderKind = .openAICompatible, settings: ModelSettings = ModelSettings()) -> ModelConnectionProfile {
        ModelConnectionProfile(name: "Test server", kind: kind, endpoint: "https://models.example.test", selectedModel: "exact-model-id", settings: settings)
    }

    func testProfilesNormalizeBaseURLsAndRejectUnsafeOrInvalidInput() throws {
        XCTAssertEqual(try ModelEndpoint.validated("http://localhost:1234/", kind: .openAICompatible).absoluteString, "http://localhost:1234/v1")
        XCTAssertEqual(try ModelEndpoint.validated("https://models.example.test/gateway/api/", kind: .ollama).absoluteString, "https://models.example.test/gateway")
        for value in ["http://models.example.test", "https://user:password@models.example.test", "https://models.example.test?key=secret", "https://models.example.test#key", "file:///tmp/model", "https://models.example.test/../v1"] {
            XCTAssertThrowsError(try ModelEndpoint.validated(value, kind: .openAICompatible), value)
        }
        XCTAssertThrowsError(try ModelSettings(contextTokens: 100).validated())
        XCTAssertThrowsError(try ModelSettings(temperature: .nan).validated())
        XCTAssertThrowsError(try ModelSettings(topP: 2).validated())
        XCTAssertThrowsError(try ModelSettings(contextTokens: 2_048, maxOutputTokens: 2_048).validated())
        XCTAssertThrowsError(try ModelEndpoint.validateModelID("model\nsecret"))
        XCTAssertThrowsError(try OpenAICompatibleClient(connection: profile(), apiKey: "key\r\nInjected: value"))
        XCTAssertThrowsError(try profile(settings: ModelSettings(thinking: true)).validated())
    }

    func testSettingsAndProfileRoundTripWithoutCredentials() throws {
        let value = profile(settings: ModelSettings(contextTokens: 16_384, maxOutputTokens: 512, temperature: 0.2, topP: 0.9))
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ModelConnectionProfile.self, from: data), value)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("apiKey"))
    }

    func testOpenAIModelDiscoveryPreservesOnlyAdvertisedVariantMetadata() async throws {
        ProviderURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            return (200, #"{"data":[{"id":"exact-Q4-variant","quantization":"Q4_K_M","parameter_size":"8B","capabilities":["tools"]},{"id":"plain-model"},{"id":"plain-model"}]}"#)
        }
        let client = try OpenAICompatibleClient(connection: profile(), apiKey: "test-key", configuration: configuration())
        let models = try await client.models()
        XCTAssertEqual(models.map(\.name), ["exact-Q4-variant", "plain-model"])
        XCTAssertEqual(models[0].quantization, "Q4_K_M")
        XCTAssertNil(models[1].quantization)
    }

    func testManualModelChatStreamsSSEWithCommentsUnicodeAndSavedSettings() async throws {
        ProviderURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let body = try providerBody(request)
            XCTAssertEqual(body["model"] as? String, "manual/model-id")
            XCTAssertEqual(body["max_tokens"] as? Int, 700)
            XCTAssertEqual(body["temperature"] as? Double, 0.2)
            XCTAssertEqual(body["top_p"] as? Double, 0.8)
            XCTAssertNil(body["quantization"])
            return (200, ": heartbeat\r\n\r\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello \"}}]}\r\n\r\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"世界\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
        }
        let client = try OpenAICompatibleClient(connection: profile(settings: ModelSettings(contextTokens: 16_384, maxOutputTokens: 700, temperature: 0.2, topP: 0.8)), configuration: configuration())
        let output = try await client.chat(model: "manual/model-id", messages: [ChatMessage(role: "user", content: "Hi")]) { _ in }
        XCTAssertEqual(output, "Hello 世界")
    }

    func testMissingDiscoveryAllowsManualModelAndToolProbeIsDataOnly() async throws {
        ProviderURLProtocol.state.set { request in
            if request.url?.path == "/v1/models" { return (404, "missing") }
            let body = try providerBody(request)
            let messages = body["messages"] as! [[String: Any]]
            let prompt = messages[0]["content"] as! String
            let nonce = prompt.components(separatedBy: "nonce ")[1].components(separatedBy: ".")[0]
            let choice = body["tool_choice"] as! [String: Any]
            XCTAssertEqual((choice["function"] as? [String: String])?["name"], "vyron_check_tools")
            let arguments = String(decoding: try JSONSerialization.data(withJSONObject: ["nonce": nonce]), as: UTF8.self)
            let reply: [String: Any] = ["choices": [["finish_reason": "tool_calls", "message": ["role": "assistant", "tool_calls": [["id": "probe-id", "type": "function", "function": ["name": "vyron_check_tools", "arguments": arguments]]]]]]]
            return (200, String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self))
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        do { _ = try await client.models(); XCTFail("Expected discovery fallback") }
        catch { XCTAssertEqual(error as? ModelProviderError, .modelListUnavailable) }
        let model = try await client.developmentModel(model: "manual/model-id", automaticModelSelection: false, effort: .balanced)
        XCTAssertEqual(model.name, "manual/model-id")
        XCTAssertEqual(model.capabilities, ["tools"])
    }

    func testOpenAIToolCallIDsSurviveAssistantAndToolResultRoundTrip() async throws {
        ProviderURLProtocol.state.set { request in
            if request.url?.path == "/v1/models" { return (200, #"{"data":[{"id":"tiny-model","capabilities":["tools"]}]}"#) }
            let body = try providerBody(request)
            let messages = body["messages"] as! [[String: Any]]
            let tools = body["tools"] as! [[String: Any]]
            let names = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
            XCTAssertEqual(
                names,
                ["list_files", "read_file", "search", VyronUserInputTool.name,
                 VyronDevelopmentPlanTool.name, VyronDevelopmentResumeTool.name],
                "Plan mode exposes only read, question, planning, and continuation tools"
            )
            XCTAssertNil(body["temperature"], "An unspecified temperature must preserve the provider default")
            if messages.last?["role"] as? String == "tool" {
                XCTAssertEqual(messages.last?["tool_call_id"] as? String, "call-exact-id")
                let calls = messages[messages.count - 2]["tool_calls"] as! [[String: Any]]
                XCTAssertEqual(calls[0]["id"] as? String, "call-exact-id")
                XCTAssertEqual((calls[0]["function"] as? [String: Any])?["arguments"] as? String, "{\"limit\":10}")
                return (200, #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Read complete."}}]}"#)
            }
            return (200, #"{"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":"call-exact-id","type":"function","function":{"name":"list_files","arguments":"{\"limit\":10}"}}]}}]}"#)
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        let base = [DevelopmentMessage(role: "user", content: "Inspect")]
        let first = try await client.developmentStep(model: "tiny-model", messages: base, mode: .plan)
        XCTAssertEqual(first.message.toolCalls?.first?.id, "call-exact-id")
        let next = try await client.developmentStep(model: "tiny-model", messages: base + [first.message, DevelopmentMessage(role: "tool", content: "files", toolName: "list_files", toolCallID: "call-exact-id")], mode: .plan)
        XCTAssertEqual(next.message.content, "Read complete.")
    }

    func testConfiguredOllamaSupportsSmallToolModelAndAppliesSettings() async throws {
        ProviderURLProtocol.state.set { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            switch request.url?.path {
            case "/api/tags": return (200, #"{"models":[{"name":"tiny:1b","size":100,"capabilities":["completion","tools"]}]}"#)
            case "/api/show": return (200, #"{"capabilities":["completion","tools"]}"#)
            case "/api/chat":
                let options = try providerBody(request)["options"] as! [String: Any]
                XCTAssertEqual(options["num_ctx"] as? Int, 16_384)
                XCTAssertEqual(options["num_predict"] as? Int, 700)
                XCTAssertEqual(options["temperature"] as? Double, 0.2)
                XCTAssertEqual(options["top_p"] as? Double, 0.8)
                return (200, #"{"message":{"role":"assistant","content":"Ready"},"done":true}"#)
            default: XCTFail("Unexpected path"); return (404, "")
            }
        }
        let client = try OllamaClient(connection: profile(kind: .ollama, settings: ModelSettings(contextTokens: 16_384, maxOutputTokens: 700, temperature: 0.2, topP: 0.8)), apiKey: "test-key", configuration: configuration())
        let selected = try await client.developmentModel(model: "tiny:1b", automaticModelSelection: false, effort: .balanced)
        XCTAssertEqual(selected.name, "tiny:1b")
        let result = try await client.developmentStep(model: "tiny:1b", messages: [DevelopmentMessage(role: "user", content: "Inspect")])
        XCTAssertEqual(result.message.content, "Ready")
    }

    func testServerErrorsNeverEchoCredentialsOrResponseBodies() async throws {
        ProviderURLProtocol.state.set { _ in (401, #"{"error":{"message":"secret-key echoed by server"}}"#) }
        let client = try OpenAICompatibleClient(connection: profile(), apiKey: "secret-key", configuration: configuration())
        do { _ = try await client.models(); XCTFail("Expected authorization error") }
        catch {
            XCTAssertEqual(error as? ModelProviderError, .http(401))
            XCTAssertFalse(error.localizedDescription.contains("secret-key"))
        }
        let ollama = try OllamaClient(connection: profile(kind: .ollama), apiKey: "secret-key", configuration: configuration())
        do { _ = try await ollama.models(); XCTFail("Expected authorization error") }
        catch { XCTAssertEqual(error as? ModelProviderError, .http(401)); XCTAssertFalse(error.localizedDescription.contains("secret-key")) }
    }

    func testExplicitLargeContextAndOutputAreAppliedWithoutSilentEffortCaps() async throws {
        ProviderURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags": return (200, #"{"models":[{"name":"tiny:1b","size":100,"capabilities":["tools"]}]}"#)
            case "/api/show": return (200, #"{"capabilities":["tools"],"model_info":{"test.context_length":131072}}"#)
            case "/api/chat":
                let options = try providerBody(request)["options"] as! [String: Any]
                XCTAssertEqual(options["num_ctx"] as? Int, 65_536)
                XCTAssertEqual(options["num_predict"] as? Int, 8_192)
                return (200, #"{"message":{"role":"assistant","content":"Ready"},"done":true}"#)
            case "/v1/models": return (200, #"{"data":[{"id":"remote","capabilities":["tools"]}]}"#)
            case "/v1/chat/completions":
                XCTAssertEqual(try providerBody(request)["max_tokens"] as? Int, 8_192)
                return (200, #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Ready"}}]}"#)
            default: XCTFail("Unexpected path"); return (404, "")
            }
        }
        let settings = ModelSettings(contextTokens: 65_536, maxOutputTokens: 8_192)
        let ollama = try OllamaClient(connection: profile(kind: .ollama, settings: settings), configuration: configuration())
        _ = try await ollama.developmentStep(model: "tiny:1b", messages: [DevelopmentMessage(role: "user", content: "Inspect")], effort: .quick)
        let compatible = try OpenAICompatibleClient(connection: profile(settings: settings), configuration: configuration())
        _ = try await compatible.developmentStep(model: "remote", messages: [DevelopmentMessage(role: "user", content: "Inspect")], effort: .quick)
    }

    func testOllamaRejectsContextBeyondAdvertisedModelLimitBeforeInference() async throws {
        ProviderURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, #"{"models":[{"name":"tiny:1b","size":100}]}"#) }
            XCTAssertEqual(request.url?.path, "/api/show", "An unsupported context must not reach inference")
            return (200, #"{"model_info":{"test.context_length":8192}}"#)
        }
        let client = try OllamaClient(connection: profile(kind: .ollama, settings: ModelSettings(contextTokens: 65_536)), configuration: configuration())
        do { _ = try await client.chat(model: "tiny:1b", messages: [ChatMessage(role: "user", content: "Hi")]) { _ in }; XCTFail("Expected context validation") }
        catch { guard case .invalidSettings = error as? ModelProviderError else { return XCTFail("Expected a settings error, got \(error)") } }
    }

    func testOpenAIAdaptsTokenLimitOnlyAfterExplicitUnsupportedParameterError() async throws {
        ProviderURLProtocol.state.set { request in
            let body = try providerBody(request)
            if body["max_tokens"] != nil { return (400, #"{"error":{"message":"Unsupported parameter: 'max_tokens'. Use 'max_completion_tokens' instead."}}"#) }
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 900)
            return (200, "data: {\"choices\":[{\"delta\":{\"content\":\"Ready\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
        }
        let client = try OpenAICompatibleClient(connection: profile(settings: ModelSettings(maxOutputTokens: 900)), configuration: configuration())
        let result = try await client.chat(model: "reasoning-model", messages: [ChatMessage(role: "user", content: "Hi")]) { _ in }
        XCTAssertEqual(result, "Ready")
    }

    func testOpenAIRejectsTruncatedStreamsAndEmptyCompletions() async throws {
        ProviderURLProtocol.state.set { request in
            if request.url?.path == "/v1/models" { return (200, #"{"data":[{"id":"remote","capabilities":["tools"]}]}"#) }
            if try providerBody(request)["stream"] as? Bool == true {
                return (200, "data: {\"choices\":[{\"delta\":{\"content\":\"Partial\"}}]}\n\n")
            }
            return (200, #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":""}}]}"#)
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        do { _ = try await client.chat(model: "remote", messages: [ChatMessage(role: "user", content: "Hi")]) { _ in }; XCTFail("Expected truncation error") }
        catch { guard case .invalidResponse = error as? ModelProviderError else { return XCTFail("Expected response error") } }
        do { _ = try await client.developmentStep(model: "remote", messages: [DevelopmentMessage(role: "user", content: "Inspect")]); XCTFail("Expected empty response rejection") }
        catch { guard case .invalidResponse = error as? ModelProviderError else { return XCTFail("Expected response error") } }
    }

    func testRedirectDelegateRejectsNewDestination() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://another.example.test")!)
        let response = HTTPURLResponse(url: URL(string: "https://models.example.test")!, statusCode: 307, httpVersion: nil, headerFields: ["Location": request.url!.absoluteString])!
        ProviderRejectRedirects().urlSession(session, task: session.dataTask(with: request), willPerformHTTPRedirection: response, newRequest: request) { redirected in XCTAssertNil(redirected) }
    }
}
