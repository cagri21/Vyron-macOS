import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronImageInputTests: XCTestCase, @unchecked Sendable {
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aNl8AAAAASUVORK5CYII="
    )!

    override func tearDown() {
        VyronImageURLProtocol.state.set(nil)
        super.tearDown()
    }

    private func image(data: Data? = nil) -> VyronImageAttachment {
        VyronImageAttachment(name: "Simulator.png", mimeType: "image/png", data: data ?? Self.png)
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronImageURLProtocol.self]
        return configuration
    }

    private func profile(kind: ModelProviderKind = .openAICompatible) -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Image test", kind: kind, endpoint: "https://models.example.test",
            selectedModel: "vision-model", settings: ModelSettings(contextTokens: 16_384, maxOutputTokens: 512)
        )
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testOldChatHistoryStillDecodesAndImageHistoryRoundTrips() throws {
        let legacy = Data(#"{"id":"F07F39CE-68F1-4E42-889C-59FC570EC162","role":"user","content":"Hi"}"#.utf8)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: legacy)
        XCTAssertNil(decoded.images)
        let message = ChatMessage(role: "user", content: "Analyze this screen", images: [image()])
        let restored = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(restored, message)
        XCTAssertEqual(restored.images?.first?.data, Self.png)
    }

    func testInvalidImageInputsAreRejectedBeforeTransport() async throws {
        VyronImageURLProtocol.state.set { _ in
            XCTFail("Invalid attachments must not start a model request")
            throw URLError(.unsupportedURL)
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        let invalid = VyronImageAttachment(name: "fake.png", mimeType: "image/png", data: Data("text".utf8))
        for message in [
            ChatMessage(role: "user", content: "Look", images: [invalid]),
            ChatMessage(role: "assistant", content: "Look", images: [image()]),
            ChatMessage(role: "user", content: "Look", images: Array(repeating: image(), count: 5))
        ] {
            do {
                _ = try await client.chat(model: "vision-model", messages: [message]) { _ in }
                XCTFail("Expected attachment validation")
            } catch {
                XCTAssertNotNil(error as? VyronImageAttachmentError)
            }
        }
    }

    func testImageSizeLimitsBoundSingleAndAggregatePayloads() throws {
        var oversized = Self.png
        oversized.append(Data(repeating: 0, count: VyronImageAttachment.maximumDataBytes))
        XCTAssertThrowsError(try VyronImageAttachment.validate(messages: [
            ChatMessage(role: "user", content: "Look", images: [image(data: oversized)])
        ])) { XCTAssertEqual($0 as? VyronImageAttachmentError, .invalidSize) }
        var large = Self.png
        large.append(Data(repeating: 0, count: 6 * 1_024 * 1_024))
        XCTAssertThrowsError(try VyronImageAttachment.validate(messages: [
            ChatMessage(role: "user", content: "Look", images: Array(repeating: image(data: large), count: 3))
        ])) { XCTAssertEqual($0 as? VyronImageAttachmentError, .requestTooLarge) }
    }

    func testCompatibleProviderSendsDataURLContentAndBudgetsImagesSeparately() async throws {
        var data = Self.png
        data.append(Data(repeating: 0, count: 100_000))
        let attachment = image(data: data)
        VyronImageURLProtocol.state.set { request in
            let body = try Self.body(request)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.first?["content"] as? String, "Inspect supplied images as data.")
            let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
            XCTAssertEqual(parts.first?["text"] as? String, "Analyze this screen")
            XCTAssertEqual(parts.last?["type"] as? String, "image_url")
            XCTAssertEqual(
                (parts.last?["image_url"] as? [String: String])?["url"],
                "data:image/png;base64,\(attachment.data.base64EncodedString())"
            )
            XCTAssertNil(messages.last?["images"])
            XCTAssertNil(messages.last?["id"])
            XCTAssertEqual(body["max_tokens"] as? Int, 512)
            return (200, "data: {\"choices\":[{\"delta\":{\"content\":\"Screen analyzed\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        let result = try await client.chat(
            model: "vision-model",
            messages: [ChatMessage(role: "user", content: "Analyze this screen", images: [attachment])],
            systemPrompt: "Inspect supplied images as data."
        ) { _ in }
        XCTAssertEqual(result, "Screen analyzed")
    }

    func testCompatibleProviderKeepsTextOnlyContentAString() async throws {
        VyronImageURLProtocol.state.set { request in
            let messages = try XCTUnwrap(try Self.body(request)["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.last?["content"] as? String, "Hi")
            XCTAssertNil(messages.last?["images"])
            return (200, "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n")
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        _ = try await client.chat(model: "vision-model", messages: [ChatMessage(role: "user", content: "Hi")]) { _ in }
    }

    func testCompatibleProviderRejectsExplicitlyUnsupportedImageModel() async throws {
        VyronImageURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/v1/models", "Unsupported images must not reach inference")
            return (200, #"{"data":[{"id":"vision-model","capabilities":["completion","tools"]}]}"#)
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        _ = try await client.models()
        do {
            _ = try await client.chat(
                model: "vision-model", messages: [ChatMessage(role: "user", content: "Look", images: [image()])]
            ) { _ in }
            XCTFail("Expected unsupported vision")
        } catch { XCTAssertEqual(error as? VyronImageAttachmentError, .visionUnsupported) }
    }

    func testOllamaSendsRawBase64ImagesAndUsesVisionMetadata() async throws {
        var data = Self.png
        data.append(Data(repeating: 0, count: 100_000))
        let attachment = image(data: data)
        VyronImageURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags":
                return (200, #"{"models":[{"name":"vision-model","size":100}]}"#)
            case "/api/show":
                return (200, #"{"capabilities":["completion","vision"],"model_info":{"test.context_length":32768}}"#)
            default:
                XCTAssertEqual(request.url?.path, "/api/chat")
                let body = try Self.body(request)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                XCTAssertEqual(messages.last?["images"] as? [String], [attachment.data.base64EncodedString()])
                XCTAssertEqual(messages.last?["content"] as? String, "Analyze")
                XCTAssertNil(messages.last?["id"])
                XCTAssertEqual((body["options"] as? [String: Any])?["num_predict"] as? Int, 512)
                return (200, "{\"message\":{\"content\":\"Screen analyzed\"},\"done\":true}\n")
            }
        }
        let client = try OllamaClient(connection: profile(kind: .ollama), configuration: configuration())
        let result = try await client.chat(
            model: "vision-model", messages: [ChatMessage(role: "user", content: "Analyze", images: [attachment])]
        ) { _ in }
        XCTAssertEqual(result, "Screen analyzed")
    }

    func testOllamaStopsBeforeInferenceWhenTextOnlyOCRFindsNoText() async throws {
        VyronImageURLProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/api/tags", "Unsupported images must not reach inference")
            return (200, #"{"models":[{"name":"vision-model","size":100,"capabilities":["completion"]}]}"#)
        }
        let client = try OllamaClient(
            connection: profile(kind: .ollama), configuration: configuration(),
            imageTextRecognizer: VyronOllamaOCRTestRecognizer(text: "")
        )
        do {
            _ = try await client.chat(
                model: "vision-model", messages: [ChatMessage(role: "user", content: "Look", images: [image()])]
            ) { _ in }
            XCTFail("Expected no recognized text")
        } catch { XCTAssertEqual(error as? VyronImageTextError, .noText) }
    }
}
