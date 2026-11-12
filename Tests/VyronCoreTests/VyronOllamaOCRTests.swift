import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaOCRTests: XCTestCase {
    override nonisolated func tearDown() {
        VyronImageURLProtocol.state.set(nil)
        super.tearDown()
    }

    func testTextOnlyChatSendsExtractedTextAndKeepsTheSelectedModel() async throws {
        let image = try VyronOllamaOCRTestSupport.image()
        let recognizer = VyronOllamaOCRTestRecognizer(text: VyronOllamaOCRTestSupport.recognizedText)
        let messages = [ChatMessage(role: "user", content: "Explain this build error.", images: [image])]
        VyronImageURLProtocol.state.set { request in
            if let metadata = VyronOllamaOCRTestSupport.metadata(for: request) { return metadata }
            XCTAssertEqual(request.url?.path, "/api/chat")
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(body["model"] as? String, VyronOllamaOCRTestSupport.model)
            let wire = try VyronOllamaOCRTestSupport.messages(in: request)
            VyronOllamaOCRTestSupport.assertNoPixels(wire)
            let user = try XCTUnwrap(wire.last?["content"] as? String)
            XCTAssertTrue(user.contains("Explain this build error."))
            XCTAssertTrue(user.contains(VyronOllamaOCRTestSupport.recognizedText))
            XCTAssertTrue(user.contains(image.name))
            return (200, VyronOllamaOCRTestSupport.reply)
        }
        let client = try VyronOllamaOCRTestSupport.client(recognizer: recognizer)

        _ = try await client.chat(model: VyronOllamaOCRTestSupport.model, messages: messages) { _ in }

        XCTAssertEqual(messages.first?.images, [image], "Saved history must retain its original pixels.")
        XCTAssertEqual(messages.first?.content, "Explain this build error.")
        let calls = await recognizer.calls
        XCTAssertEqual(calls, 1)
    }

    func testTextFollowUpConvertsTheEarlierImageWithoutChangingTheNewQuestion() async throws {
        let image = try VyronOllamaOCRTestSupport.image()
        let recognizer = VyronOllamaOCRTestRecognizer(text: VyronOllamaOCRTestSupport.recognizedText)
        let messages = [
            ChatMessage(role: "user", content: "Inspect this error.", images: [image]),
            ChatMessage(role: "assistant", content: "It reports a missing setting."),
            ChatMessage(role: "user", content: "Which exact setting does it mention?")
        ]
        VyronImageURLProtocol.state.set { request in
            if let metadata = VyronOllamaOCRTestSupport.metadata(for: request) { return metadata }
            let wire = try VyronOllamaOCRTestSupport.messages(in: request)
            VyronOllamaOCRTestSupport.assertNoPixels(wire)
            XCTAssertTrue((wire.first?["content"] as? String)?.contains(
                VyronOllamaOCRTestSupport.recognizedText
            ) == true)
            XCTAssertEqual(wire.last?["content"] as? String, "Which exact setting does it mention?")
            XCTAssertEqual(wire.dropFirst().first?["content"] as? String, "It reports a missing setting.")
            return (200, VyronOllamaOCRTestSupport.reply)
        }
        let client = try VyronOllamaOCRTestSupport.client(recognizer: recognizer)

        _ = try await client.chat(model: VyronOllamaOCRTestSupport.model, messages: messages) { _ in }

        XCTAssertEqual(messages.first?.images, [image])
        let calls = await recognizer.calls
        XCTAssertEqual(calls, 1)
    }

    func testDevelopmentOCRPreservesAgentAndPlanToolContracts() async throws {
        let image = try VyronOllamaOCRTestSupport.image()
        let call = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("README.md")], id: "read-42")
        let messages = [
            DevelopmentMessage(role: "user", content: "Inspect this build error.", images: [image]),
            DevelopmentMessage(role: "assistant", toolCalls: [call]),
            DevelopmentMessage(role: "tool", content: "Project setup", toolName: "read_file", toolCallID: "read-42"),
            DevelopmentMessage(role: "user", content: "Explain it using the project setup.")
        ]
        for mode in [DevelopmentMode.agent, .plan] {
            let recognizer = VyronOllamaOCRTestRecognizer(text: VyronOllamaOCRTestSupport.recognizedText)
            VyronImageURLProtocol.state.set { request in
                if let metadata = VyronOllamaOCRTestSupport.metadata(for: request) { return metadata }
                let body = try VyronResponsesTestSupport.body(request)
                XCTAssertEqual(body["model"] as? String, VyronOllamaOCRTestSupport.model)
                let wire = try VyronOllamaOCRTestSupport.messages(in: request)
                VyronOllamaOCRTestSupport.assertNoPixels(wire)
                XCTAssertTrue(wire.contains {
                    ($0["content"] as? String)?.contains(VyronOllamaOCRTestSupport.recognizedText) == true
                })
                let tool = try XCTUnwrap(wire.first { $0["role"] as? String == "tool" })
                XCTAssertEqual(tool["content"] as? String, "Project setup")
                XCTAssertEqual(tool["tool_name"] as? String, "read_file")
                XCTAssertEqual(tool["tool_call_id"] as? String, "read-42")
                let assistant = try XCTUnwrap(wire.first { $0["role"] as? String == "assistant" })
                let calls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
                XCTAssertEqual(calls.first?["id"] as? String, "read-42")
                let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
                let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
                XCTAssertTrue(names.contains("read_file"))
                XCTAssertEqual(names.contains("write_file"), mode == .agent)
                return (200, VyronOllamaOCRTestSupport.reply)
            }
            let client = try VyronOllamaOCRTestSupport.client(recognizer: recognizer)

            _ = try await client.developmentStep(
                model: VyronOllamaOCRTestSupport.model, messages: messages, effort: .quick, mode: mode
            )

            XCTAssertEqual(messages.first?.images, [image])
            let calls = await recognizer.calls
            XCTAssertEqual(calls, 1)
        }
    }

    func testVisionChatBypassesOCRAndSendsTheOriginalPixels() async throws {
        let image = try VyronOllamaOCRTestSupport.image()
        let recognizer = VyronOllamaOCRTestRecognizer(text: "", shouldFail: true)
        VyronImageURLProtocol.state.set { request in
            if let metadata = VyronOllamaOCRTestSupport.metadata(for: request, vision: true) { return metadata }
            let wire = try VyronOllamaOCRTestSupport.messages(in: request)
            XCTAssertEqual(wire.last?["images"] as? [String], [image.data.base64EncodedString()])
            XCTAssertEqual(wire.last?["content"] as? String, "Inspect this image.")
            return (200, VyronOllamaOCRTestSupport.reply)
        }
        let client = try VyronOllamaOCRTestSupport.client(recognizer: recognizer)

        _ = try await client.chat(model: VyronOllamaOCRTestSupport.model, messages: [
            ChatMessage(role: "user", content: "Inspect this image.", images: [image])
        ]) { _ in }

        let calls = await recognizer.calls
        XCTAssertEqual(calls, 0)
    }

    func testEmptyRecognitionStopsInferenceAndAllowsRetry() async throws {
        let image = try VyronOllamaOCRTestSupport.image()
        let recognizer = VyronOllamaOCRTestRecognizer(text: "  \n")
        let client = try VyronOllamaOCRTestSupport.client(recognizer: recognizer)
        let messages = [ChatMessage(role: "user", content: "Inspect", images: [image])]
        installMetadataOnlyTransport()
        do {
            _ = try await client.chat(model: VyronOllamaOCRTestSupport.model, messages: messages) { _ in }
            XCTFail("Empty recognition must fail before model inference.")
        } catch {
            XCTAssertEqual(error as? VyronImageTextError, .noText)
        }
        await recognizer.recover(with: VyronOllamaOCRTestSupport.recognizedText)
        installSuccessfulTransport()

        _ = try await client.chat(model: VyronOllamaOCRTestSupport.model, messages: messages) { _ in }

        XCTAssertEqual(messages.first?.images, [image])
        let calls = await recognizer.calls
        XCTAssertEqual(calls, 2)
    }

    func testRecognitionErrorStopsDevelopmentInferenceAndAllowsRetry() async throws {
        let image = try VyronOllamaOCRTestSupport.image()
        let recognizer = VyronOllamaOCRTestRecognizer(text: "", shouldFail: true)
        let client = try VyronOllamaOCRTestSupport.client(recognizer: recognizer)
        let messages = [DevelopmentMessage(role: "user", content: "Inspect", images: [image])]
        installMetadataOnlyTransport()
        do {
            _ = try await client.developmentStep(model: VyronOllamaOCRTestSupport.model, messages: messages)
            XCTFail("Recognition errors must fail before model inference.")
        } catch {
            XCTAssertEqual(error as? VyronImageTextError, .recognitionFailed)
        }
        await recognizer.recover(with: VyronOllamaOCRTestSupport.recognizedText)
        installSuccessfulTransport()

        _ = try await client.developmentStep(model: VyronOllamaOCRTestSupport.model, messages: messages)

        XCTAssertEqual(messages.first?.images, [image])
        let calls = await recognizer.calls
        XCTAssertEqual(calls, 2)
    }

    func testCancellationDuringChatOCRDoesNotStartInference() async throws {
        let image = try VyronOllamaOCRTestSupport.image()
        let recognizer = VyronOllamaOCRTestRecognizer(text: "unused", waitsForCancellation: true)
        let client = try VyronOllamaOCRTestSupport.client(recognizer: recognizer)
        installMetadataOnlyTransport()
        let operation = Task {
            try await client.chat(model: VyronOllamaOCRTestSupport.model, messages: [
                ChatMessage(role: "user", content: "Inspect", images: [image])
            ]) { _ in }
        }
        defer { operation.cancel() }
        try await waitForRecognition(recognizer)
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Cancelled OCR must stop the request.")
        } catch is CancellationError {
            XCTAssertTrue(operation.isCancelled)
        } catch {
            XCTFail("Expected cancellation, received \(error).")
        }
    }

    func testCancellationDuringDevelopmentOCRDoesNotStartInference() async throws {
        let image = try VyronOllamaOCRTestSupport.image()
        let recognizer = VyronOllamaOCRTestRecognizer(text: "unused", waitsForCancellation: true)
        let client = try VyronOllamaOCRTestSupport.client(recognizer: recognizer)
        installMetadataOnlyTransport()
        let operation = Task {
            try await client.developmentStep(model: VyronOllamaOCRTestSupport.model, messages: [
                DevelopmentMessage(role: "user", content: "Inspect", images: [image])
            ])
        }
        defer { operation.cancel() }
        try await waitForRecognition(recognizer)
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Cancelled OCR must stop the request.")
        } catch is CancellationError {
            XCTAssertTrue(operation.isCancelled)
        } catch {
            XCTFail("Expected cancellation, received \(error).")
        }
    }

    private func waitForRecognition(_ recognizer: VyronOllamaOCRTestRecognizer) async throws {
        for _ in 0..<500 {
            if await recognizer.calls > 0 { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The local recognizer was not called.")
        throw CancellationError()
    }

    private func installMetadataOnlyTransport() {
        VyronImageURLProtocol.state.set { request in
            if let metadata = VyronOllamaOCRTestSupport.metadata(for: request) { return metadata }
            XCTFail("OCR failure or cancellation must stop before model inference.")
            throw URLError(.unsupportedURL)
        }
    }

    private func installSuccessfulTransport() {
        VyronImageURLProtocol.state.set { request in
            if let metadata = VyronOllamaOCRTestSupport.metadata(for: request) { return metadata }
            let wire = try VyronOllamaOCRTestSupport.messages(in: request)
            VyronOllamaOCRTestSupport.assertNoPixels(wire)
            XCTAssertTrue(wire.contains {
                ($0["content"] as? String)?.contains(VyronOllamaOCRTestSupport.recognizedText) == true
            })
            return (200, VyronOllamaOCRTestSupport.reply)
        }
    }
}
