import Foundation
import VyronDevelopment
import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronDevelopmentImageInputTests: XCTestCase, @unchecked Sendable {
    private func image() throws -> VyronImageAttachment {
        var data = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aNl8AAAAASUVORK5CYII="
        ))
        data.append(Data(repeating: 0, count: 100_000))
        return VyronImageAttachment(name: "Reference.png", mimeType: "image/png", data: data)
    }

    private func configuration() -> URLSessionConfiguration {
        let value = URLSessionConfiguration.ephemeral
        value.protocolClasses = [VyronImageURLProtocol.self]
        return value
    }

    private func profile(kind: ModelProviderKind = .openAICompatible) -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Image development test", kind: kind, endpoint: "https://models.example.test",
            selectedModel: "vision-model", settings: ModelSettings(contextTokens: 32_768, maxOutputTokens: 512)
        )
    }

    override func tearDown() async throws {
        VyronImageURLProtocol.state.set(nil)
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testLegacyDevelopmentHistoryAndImageCopiesPreserveTheirContracts() throws {
        let legacy = try JSONDecoder().decode(
            DevelopmentMessage.self, from: Data(#"{"role":"user","content":"Inspect"}"#.utf8)
        )
        XCTAssertNil(legacy.images)
        let attachment = try image()
        let original = DevelopmentMessage(role: "user", content: "Inspect", images: [attachment])
        let restored = try JSONDecoder().decode(
            DevelopmentMessage.self, from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(restored, original)
        let annotated = DevelopmentMessage(message: original, continuation: VyronModelContinuation(
            source: "foreign", model: "foreign-model", state: Data("opaque".utf8)
        ))
        XCTAssertEqual(annotated.images, [attachment])
        XCTAssertEqual(annotated.discardingContinuation(), original)
        let fields = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(legacy)
        ) as? [String: Any])
        XCTAssertNil(fields["images"], "Legacy text-only storage does not gain a required field")
    }

    func testLargeImagePayloadDoesNotConsumeTextBudgetOrDisappearDuringCompaction() throws {
        let attachment = try image()
        let base = developmentBaseMessages(
            system: "Inspect supplied images as reference data.", goal: "Build this interface",
            conversationContext: nil, guidance: VyronDevelopmentSessionGuidance(images: [attachment])
        )
        XCTAssertEqual(base.last?.images, [attachment])
        XCTAssertTrue(base.last?.content.contains("Reference.png") == true)
        XCTAssertGreaterThan(try JSONEncoder().encode(base).count, VyronDevelopmentMessageBudget.standard.maximumBytes)
        let bounded = try boundedDevelopmentMessages(base: base, exchanges: [])
        let compacted = try VyronDevelopmentRequestBudget.messages(
            bounded, tools: [], budget: .init(contextTokens: 16_384)
        )
        XCTAssertEqual(compacted, base)
        XCTAssertEqual(
            try VyronDevelopmentImageContext.estimatedMessageBytes(base)
                - VyronDevelopmentImageContext.textMessageBytes(base),
            VyronImageAttachment.estimatedContextTokens
        )
        XCTAssertThrowsError(try VyronDevelopmentRequestBudget.messages(
            base, tools: [], budget: .init(contextTokens: 4_096)
        )) {
            XCTAssertEqual($0 as? DevelopmentAgentError, .contextBudget)
        }
        let options = try developmentRequestOptions(
            messages: base, tools: [], effort: .quick, limits: .init(maximumContext: 16_384, outputOverride: 512)
        )
        XCTAssertEqual(options.num_predict, 512)
    }

    func testInvalidImageRolesAndAggregateCountsFailBeforeProviderRequests() async throws {
        let attachment = try image()
        VyronImageURLProtocol.state.set { _ in
            XCTFail("Invalid image messages must not start a provider request")
            throw URLError(.unsupportedURL)
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        for message in [
            DevelopmentMessage(role: "assistant", content: "Inspect", images: [attachment]),
            DevelopmentMessage(role: "user", content: "Inspect", images: Array(repeating: attachment, count: 5))
        ] {
            do {
                _ = try await client.developmentStep(model: "vision-model", messages: [message])
                XCTFail("Expected image validation")
            } catch {
                XCTAssertNotNil(error as? VyronImageAttachmentError)
            }
        }
    }

    func testCompatibleDevelopmentSendsActualImagePartsWithNativeTools() async throws {
        let attachment = try image()
        VyronImageURLProtocol.state.set { request in
            if request.url?.path == "/v1/models" {
                return (200, #"{"data":[{"id":"vision-model","capabilities":["tools","vision"]}]}"#)
            }
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let body = try VyronResponsesTestSupport.body(request)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
            XCTAssertEqual(parts.first?["text"] as? String, "Build this")
            XCTAssertEqual(parts.last?["type"] as? String, "image_url")
            XCTAssertEqual(
                (parts.last?["image_url"] as? [String: String])?["url"],
                "data:image/png;base64," + attachment.data.base64EncodedString()
            )
            XCTAssertNil(messages.last?["images"])
            XCTAssertNotNil(body["tools"])
            XCTAssertEqual(body["max_tokens"] as? Int, 512)
            return (200, #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Ready"}}]}"#)
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        let result = try await client.developmentStep(model: "vision-model", messages: [
            DevelopmentMessage(role: "user", content: "Build this", images: [attachment])
        ])
        XCTAssertEqual(result.message.content, "Ready")
    }

    func testOllamaDevelopmentSendsRawImageBytesAndRetainsToolFormat() async throws {
        let attachment = try image()
        VyronImageURLProtocol.state.set { request in
            switch request.url?.path {
            case "/api/tags":
                return (200, #"{"models":[{"name":"vision-model","size":100,"capabilities":["tools","vision"]}]}"#)
            case "/api/show":
                return (200, #"{"capabilities":["tools","vision"],"model_info":{"test.context_length":32768}}"#)
            default:
                XCTAssertEqual(request.url?.path, "/api/chat")
                let body = try VyronResponsesTestSupport.body(request)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                XCTAssertEqual(messages.last?["images"] as? [String], [attachment.data.base64EncodedString()])
                XCTAssertEqual(messages.last?["content"] as? String, "Build this")
                XCTAssertNil(messages.last?["continuation"])
                XCTAssertNotNil(body["tools"])
                return (200, #"{"message":{"role":"assistant","content":"Ready"},"done":true}"#)
            }
        }
        let client = try OllamaClient(connection: profile(kind: .ollama), configuration: configuration())
        let result = try await client.developmentStep(model: "vision-model", messages: [
            DevelopmentMessage(role: "user", content: "Build this", images: [attachment])
        ])
        XCTAssertEqual(result.message.content, "Ready")
    }

    func testResponsesDevelopmentSendsImageInputsAndPreservesOutputBudget() async throws {
        let attachment = try image()
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            let body = try VyronResponsesTestSupport.body(request)
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            let parts = try XCTUnwrap(input.last?["content"] as? [[String: Any]])
            XCTAssertEqual(parts.first?["type"] as? String, "input_text")
            XCTAssertEqual(parts.last?["type"] as? String, "input_image")
            XCTAssertEqual(
                parts.last?["image_url"] as? String,
                "data:image/png;base64," + attachment.data.base64EncodedString()
            )
            XCTAssertEqual(body["max_output_tokens"] as? Int, 512)
            XCTAssertNotNil(body["tools"])
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.textOutput("Ready")
            ]))
        }
        let client = try VyronResponsesTestSupport.client(settings: ModelSettings(
            contextTokens: 32_768, maxOutputTokens: 512
        ))
        let result = try await client.developmentStep(model: VyronResponsesTestSupport.model, messages: [
            DevelopmentMessage(role: "user", content: "Build this", images: [attachment])
        ])
        XCTAssertEqual(result.message.content, "Ready")
    }

    func testCompatibleDevelopmentRejectsExplicitTextOnlyModelBeforeSendingPixels() async throws {
        let attachment = try image()
        VyronImageURLProtocol.state.set { request in
            switch request.url?.path {
            case "/v1/models":
                return (200, #"{"data":[{"id":"vision-model","capabilities":["tools"]}]}"#)
            default:
                XCTFail("A model explicitly missing vision must not receive an image inference request")
                throw URLError(.unsupportedURL)
            }
        }
        let client = try OpenAICompatibleClient(connection: profile(), configuration: configuration())
        do {
            _ = try await client.developmentStep(model: "vision-model", messages: [
                DevelopmentMessage(role: "user", content: "Build this", images: [attachment])
            ], effort: .quick, mode: .plan)
            XCTFail("Expected unsupported vision")
        } catch {
            XCTAssertEqual(error as? VyronImageAttachmentError, .visionUnsupported)
        }
    }

    func testAgentKeepsSelectedImageModelAndDeliversVisualContext() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { XCTFail("Could not remove temporary image-test project: \(error)") }
        }
        let attachment = try image()
        let provider = VyronDevelopmentImageTestProvider()
        let agent = DevelopmentAgent(client: provider, workspace: try DevelopmentWorkspace(rootURL: directory))
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: UUID(), responseID: UUID(),
            guidance: VyronDevelopmentSessionGuidance(images: [attachment])
        ))
        _ = try await agent.run(
            goal: "Describe the attached interface", model: "vision-model", automaticModelSelection: true,
            effort: .quick, mode: .plan, onEvent: { _ in }, approveCommand: { _ in false }
        )
        let automaticSelection = await provider.automaticSelection
        let messages = await provider.receivedMessages
        XCTAssertEqual(automaticSelection, false)
        XCTAssertEqual(messages.first { $0.images?.isEmpty == false }?.images, [attachment])
        XCTAssertTrue(messages.first?.content.contains(VyronDevelopmentImageContext.evidencePrompt) == true)
    }
}
