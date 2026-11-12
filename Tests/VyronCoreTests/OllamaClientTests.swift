import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

private final class StubState: @unchecked Sendable {
    let lock = NSLock()
    var handler: (@Sendable (URLRequest) throws -> (Int, String))?

    func set(_ handler: (@Sendable (URLRequest) throws -> (Int, String))?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func handle(_ request: URLRequest) throws -> (Int, String) {
        lock.lock()
        let action = handler
        lock.unlock()
        guard let action else { throw URLError(.unsupportedURL) }
        return try action(request)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.state.handle(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/x-ndjson"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // Several deliveries exercise URLSession's buffering across streaming lines.
            let data = Data(body.utf8)
            let middle = data.count / 2
            client?.urlProtocol(self, didLoad: Data(data.prefix(middle)))
            client?.urlProtocol(self, didLoad: Data(data.dropFirst(middle)))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private final class Values<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Value] = []
    func append(_ value: Value) { lock.withLock { items.append(value) } }
    var values: [Value] { lock.withLock { items } }
}

private func requestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        result.append(contentsOf: buffer.prefix(count))
    }
    return result
}

final class OllamaClientTests: XCTestCase, @unchecked Sendable {
    private let localCatalog = #"{"models":[{"name":"qwen3-coder:30b","size":19000000000,"details":{"parameter_size":"30.5B","quantization_level":"Q4_K_M"}}]}"#

    override func tearDown() {
        StubURLProtocol.state.set(nil)
        super.tearDown()
    }

    private func client(endpoint: String = "http://127.0.0.1:11434") -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return OllamaClient(baseURL: URL(string: endpoint)!, configuration: configuration)
    }

    func testEndpointAllowsOnlyPlainHTTPLoopbackAndCanonicalizesLocalhost() throws {
        let local = try OllamaClient.canonicalEndpoint(URL(string: "http://localhost:11434/")!)
        XCTAssertEqual(local.absoluteString, "http://127.0.0.1:11434")
        for endpoint in [
            "https://127.0.0.1:11434", "http://192.168.1.2:11434", "http://example.com",
            "http://127.0.0.1.example.com", "http://[::1]:11434", "http://user:pass@127.0.0.1",
            "http://127.0.0.1/path", "http://127.0.0.1?destination=remote", "http://127.0.0.1#fragment"
        ] {
            XCTAssertThrowsError(try OllamaClient.canonicalEndpoint(URL(string: endpoint)!)) { error in
                XCTAssertEqual(error as? LocalAIError, .invalidEndpoint, endpoint)
            }
        }
    }

    func testRemoteEndpointNeverStartsTransport() async throws {
        StubURLProtocol.state.set { _ in
            XCTFail("Invalid endpoints must not create requests")
            return (200, "{\"models\":[]}")
        }
        do {
            _ = try await client(endpoint: "http://example.com:11434").models()
            XCTFail("Expected endpoint rejection")
        } catch {
            XCTAssertEqual(error as? LocalAIError, .invalidEndpoint)
        }
    }

    func testModelListExcludesCloudMetadataAndCloudTags() async throws {
        StubURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            return (200, #"{"models":[{"name":"local:latest","size":42,"details":{"parameter_size":"8B","quantization_level":"Q4_K_M"}},{"name":"alias:latest","remote_model":"remote-model","remote_host":"https://ollama.com"},{"name":"gpt-oss:120b-cloud"}]}"#)
        }
        let models = try await client().models()
        XCTAssertEqual(models.map(\.name), ["local:latest"])
        XCTAssertEqual(models.first?.parameterSize, "8B")
        XCTAssertEqual(models.first?.size, 42)
    }

    func testChatStreamsTokensAndSendsOnlyWireMessageFields() async throws {
        let catalog = localCatalog
        StubURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, catalog) }
            XCTAssertEqual(request.url?.path, "/api/chat")
            XCTAssertEqual(request.httpMethod, "POST")
            let object = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let messages = object["messages"] as! [[String: Any]]
            XCTAssertEqual(messages[0]["role"] as? String, "system")
            XCTAssertEqual(messages[0]["content"] as? String, "Work locally.")
            XCTAssertNil(messages[1]["id"])
            let options = object["options"] as? [String: Any]
            XCTAssertEqual(options?["num_ctx"] as? Int, 32_768)
            XCTAssertEqual(options?["num_predict"] as? Int, 4_096)
            XCTAssertEqual(object["keep_alive"] as? String, "5m")
            return (200, "{\"message\":{\"content\":\"Hello \"},\"done\":false}\n\n{\"message\":{\"content\":\"世界\"},\"done\":false}\n{\"done\":true}\n")
        }
        let tokens = Values<String>()
        let output = try await client().chat(model: "qwen3-coder:30b", messages: [ChatMessage(role: "user", content: "Hi")], systemPrompt: "Work locally.") { tokens.append($0) }
        XCTAssertEqual(output, "Hello 世界")
        XCTAssertEqual(tokens.values, ["Hello ", "世界"])
    }

    func testChatRejectsRemoteAliasBeforeSendingPrompt() async throws {
        StubURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            return (200, #"{"models":[{"name":"alias:latest","remote_model":"remote-model"}]}"#)
        }
        do {
            _ = try await client().chat(model: "alias", messages: [ChatMessage(role: "user", content: "private")]) { _ in }
            XCTFail("Expected cloud alias rejection")
        } catch {
            XCTAssertEqual(error as? LocalAIError, .cloudModelNotAllowed)
        }
    }

    func testNewQwenChatKeepsNativeDefaultAndStreamsOnlyTheVisibleAnswer() async throws {
        StubURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags": return (200, #"{"models":[{"name":"qwen3.8:27b","size":18000000000}]}"#)
            case "/api/show": return (200, #"{"capabilities":["completion","tools","thinking"],"thinking":{"values":[false,true]}}"#)
            default:
                XCTAssertEqual(request.url?.path, "/api/chat")
                let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any])
                XCTAssertNil(object["think"])
                XCTAssertEqual((object["options"] as? [String: Any])?["num_ctx"] as? Int, 32_768)
                return (200, "{\"message\":{\"thinking\":\"private reasoning\",\"content\":\"\"},\"done\":false}\n{\"message\":{\"content\":\"Visible answer\"},\"done\":false}\n{\"done\":true}\n")
            }
        }
        let tokens = Values<String>()
        let output = try await client().chat(model: "qwen3.8:27b", messages: [ChatMessage(role: "user", content: "Hello")]) { tokens.append($0) }
        XCTAssertEqual(output, "Visible answer")
        XCTAssertEqual(tokens.values, ["Visible answer"])
    }

    func testHeavyChatKeepsEightKContextAndReducesOutputWithoutDroppingInput() async throws {
        let content = String(repeating: "x", count: 5_000)
        StubURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, #"{"models":[{"name":"qwen3-coder-next:q4_K_M","size":52000000000}]}"#) }
            XCTAssertEqual(request.url?.path, "/api/chat")
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody(request)) as? [String: Any])
            let options = try XCTUnwrap(object["options"] as? [String: Any])
            let output = try XCTUnwrap(options["num_predict"] as? Int)
            XCTAssertEqual(options["num_ctx"] as? Int, 8_192)
            XCTAssertLessThan(output, 4_096)
            XCTAssertGreaterThanOrEqual(output, 512)
            XCTAssertNil(object["think"])
            let messages = try XCTUnwrap(object["messages"] as? [[String: String]])
            XCTAssertEqual(messages.last?["content"], content)
            XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: messages).count + 2_048 + output, 8_192)
            return (200, "{\"message\":{\"content\":\"Answer\"},\"done\":true}\n")
        }
        let output = try await client().chat(model: "qwen3-coder-next:q4_K_M", messages: [ChatMessage(role: "user", content: content)]) { _ in }
        XCTAssertEqual(output, "Answer")
    }

    func testHeavyChatRejectsOversizedCompleteInputBeforeSendingIt() async throws {
        StubURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/api/tags", "Oversized input must not reach chat")
            return (200, #"{"models":[{"name":"qwen3-coder-next:q4_K_M","size":52000000000}]}"#)
        }
        do {
            _ = try await client().chat(model: "qwen3-coder-next:q4_K_M", messages: [ChatMessage(role: "user", content: String(repeating: "x", count: 7_000))]) { _ in }
            XCTFail("The 8K cap must not silently become 32K")
        } catch {
            guard case .invalidResponse(let detail) = error as? LocalAIError else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(detail.contains("context budget"))
        }
    }

    func testThinkingOnlyOrWhitespaceChatCompletionDoesNotLookSuccessful() async throws {
        let catalog = localCatalog
        for content in ["", " \n\t"] {
            let line = try JSONSerialization.data(withJSONObject: ["message": ["thinking": "hidden reasoning", "content": content], "done": true])
            let response = String(decoding: line, as: UTF8.self) + "\n"
            StubURLProtocol.state.set { request in
                request.url?.path == "/api/tags" ? (200, catalog) : (200, response)
            }
            do {
                _ = try await client().chat(model: "qwen3-coder:30b", messages: [ChatMessage(role: "user", content: "Hello")]) { _ in }
                XCTFail("A completed stream without visible text is not a successful answer")
            } catch {
                guard case .invalidResponse(let detail) = error as? LocalAIError else { return XCTFail("Unexpected error: \(error)") }
                XCTAssertTrue(detail.contains("without a visible answer"))
            }
        }
    }

    func testCloudAndHostedNamesAreRejected() throws {
        for name in ["gpt-oss:120b-cloud", "model:cloud", "https://example.com/model", "hf.co/user/model", "../model", "model\n"] {
            XCTAssertThrowsError(try OllamaClient.validateModelName(name), name)
        }
        for name in ["qwen3-coder:30b", "llama3.2", "library/qwen3:8b", "my_model:q4_K_M"] {
            XCTAssertNoThrow(try OllamaClient.validateModelName(name), name)
        }
    }

    func testIncompleteChatIsReportedAsIncomplete() async throws {
        let catalog = localCatalog
        StubURLProtocol.state.set { request in
            request.url?.path == "/api/tags" ? (200, catalog) : (200, "{\"message\":{\"content\":\"partial\"},\"done\":false}\n")
        }
        do {
            _ = try await client().chat(model: "qwen3-coder:30b", messages: []) { _ in }
            XCTFail("Expected incomplete stream rejection")
        } catch {
            XCTAssertEqual(error as? LocalAIError, .incompleteStream)
        }
    }

    func testStreamingServerErrorIsReported() async throws {
        let catalog = localCatalog
        StubURLProtocol.state.set { request in
            request.url?.path == "/api/tags" ? (200, catalog) : (200, "{\"error\":\"model needs more memory\"}\n")
        }
        do {
            _ = try await client().chat(model: "qwen3-coder:30b", messages: []) { _ in }
            XCTFail("Expected server error")
        } catch {
            XCTAssertEqual(error as? LocalAIError, .invalidResponse("model needs more memory"))
        }
    }

    func testPullReportsProgressAndRequiresSuccessMarker() async throws {
        StubURLProtocol.state.set { request in
            if request.url?.path == "/api/tags" { return (200, "{\"models\":[]}") }
            return (200, "{\"status\":\"pulling layer\",\"completed\":5,\"total\":10}\n{\"status\":\"success\"}\n")
        }
        let progress = Values<ModelPullProgress>()
        try await client().pull(model: "qwen3-coder:30b") { progress.append($0) }
        XCTAssertEqual(progress.values.first?.fraction, 0.5)
        XCTAssertEqual(progress.values.last?.status, "success")
    }

    func testMalformedStreamingJSONIsRejected() throws {
        XCTAssertThrowsError(try OllamaClient.decodeLine("not JSON") as ChatEvent)
        XCTAssertThrowsError(try OllamaClient.decodeLine(String(repeating: "x", count: 2_097_153)) as ChatEvent)
    }

    func testHTTPRedirectResponseIsNotAcceptedAsModelData() async throws {
        StubURLProtocol.state.set { _ in (302, "") }
        do {
            _ = try await client().models()
            XCTFail("Expected redirect rejection")
        } catch {
            XCTAssertEqual(error as? LocalAIError, .httpError(302, ""))
        }
    }

    func testCancellationRemainsCancellation() async throws {
        let catalog = localCatalog
        StubURLProtocol.state.set { _ in (200, catalog) }
        let localClient = client()
        let task = Task { try await localClient.models() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }
}
