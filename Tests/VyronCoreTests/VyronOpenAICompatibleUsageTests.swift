import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOpenAICompatibleUsageTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testOfficialCompatibleStreamRequestsFinalUsageAndRecordsItOnce() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual((body["stream_options"] as? [String: Bool])?["include_usage"], true)
            return VyronResponsesTestResponse(body: Self.stream(finishReason: "stop"))
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let client = try client(recorder: recorder)
        let answer = try await client.chat(
            model: "gpt-4.1", messages: [ChatMessage(role: "user", content: "Hi")]
        ) { _ in }
        XCTAssertEqual(answer, "Hello")
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.observation.model, "gpt-4.1-2025-04-14")
        XCTAssertEqual(events.first?.observation.result, .measured(.init(
            inputTokens: 10, outputTokens: 5,
            inputDetails: .init(cachedTokens: 4, cacheWrite30mTokens: 0, cacheWrite12hTokens: 0)
        )))
    }

    func testTruncatedCompatibleAnswerStillCollectsItsFinalUsageBeforeFailing() async throws {
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(body: Self.stream(finishReason: "length"))
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let client = try client(recorder: recorder)
        do {
            _ = try await client.chat(
                model: "gpt-4.1", messages: [ChatMessage(role: "user", content: "Hi")]
            ) { _ in }
            XCTFail("Truncated output must not become a successful answer")
        } catch { XCTAssertTrue(error is ModelProviderError) }
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        guard case .measured = events.first?.observation.result else { return XCTFail("Lost truncated usage") }
    }

    func testOtherCompatibleProvidersKeepTheirExistingWireAndNeverReportOpenAIUsage() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertNil(body["stream_options"])
            return VyronResponsesTestResponse(body: Self.stream(finishReason: "stop"))
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let client = try client(endpoint: "https://models.example.test/v1", recorder: recorder)
        _ = try await client.chat(model: "gpt-4.1", messages: [ChatMessage(role: "user", content: "Hi")]) { _ in }
        let events = await recorder.events
        XCTAssertTrue(events.isEmpty)
    }

    func testNonstreamDevelopmentIncludesChargedUsageEvenWhenItsOutputIsIncomplete() async throws {
        for reason in ["stop", "length"] {
            await VyronResponsesTestURLProtocol.state.reset { request, _ in
                if request.url?.path == "/v1/models" {
                    return VyronResponsesTestResponse(body: #"{"data":[{"id":"gpt-4.1","capabilities":["tools"]}]}"#)
                }
                return VyronResponsesTestResponse(body: """
                {"id":"chat_development","model":"gpt-4.1","usage":{"prompt_tokens":10,"completion_tokens":5},
                 "choices":[{"message":{"role":"assistant","content":"Plan ready"},"finish_reason":"\(reason)"}]}
                """)
            }
            let recorder = VyronOpenAIUsageTestRecorder()
            let client = try client(recorder: recorder)
            do {
                _ = try await client.developmentStep(
                    model: "gpt-4.1", messages: [DevelopmentMessage(role: "user", content: "Plan")], mode: .plan
                )
                XCTAssertEqual(reason, "stop")
            } catch {
                XCTAssertEqual(reason, "length")
                XCTAssertTrue(error is ModelProviderError)
            }
            let events = await recorder.events
            XCTAssertEqual(events.count, 1)
            guard case .measured = events.first?.observation.result else { return XCTFail("Lost development usage") }
        }
    }

    func testCancellationDuringReceiptDeliveryRetainsMeasuredUsageAndRemainsCancellation() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" {
                return VyronResponsesTestResponse(body: #"{"data":[{"id":"gpt-4.1","capabilities":["tools"]}]}"#)
            }
            return VyronResponsesTestResponse(body: """
            {"id":"chat_cancelled","model":"gpt-4.1","usage":{"prompt_tokens":10,"completion_tokens":5},
             "choices":[{"message":{"role":"assistant","content":"Plan ready"},"finish_reason":"stop"}]}
            """)
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        var profile = VyronResponsesTestSupport.profile()
        profile.selectedModel = "gpt-4.1"
        let client = try OpenAICompatibleClient(
            connection: profile, configuration: configuration, usageHandler: { event in
                await recorder.append(event)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        )
        let task = Task {
            try await client.developmentStep(
                model: "gpt-4.1", messages: [DevelopmentMessage(role: "user", content: "Plan")], mode: .plan
            )
        }
        do { _ = try await task.value; XCTFail("Cancellation must not turn into a completed answer") } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        guard case .measured = events.first?.observation.result else { return XCTFail("Lost cancelled usage") }
    }

    private func client(
        endpoint: String = "https://api.openai.com/v1",
        recorder: VyronOpenAIUsageTestRecorder
    ) throws -> OpenAICompatibleClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        var profile = VyronResponsesTestSupport.profile()
        profile.endpoint = endpoint
        profile.selectedModel = "gpt-4.1"
        return try OpenAICompatibleClient(
            connection: profile, configuration: configuration, usageHandler: { await recorder.append($0) }
        )
    }

    nonisolated private static func stream(finishReason: String) -> String {
        "data: {\"id\":\"chat_test\",\"model\":\"gpt-4.1-2025-04-14\",\"choices\":["
            + "{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":\"\(finishReason)\"}]}\n\n"
            + "data: {\"id\":\"chat_test\",\"model\":\"gpt-4.1-2025-04-14\",\"choices\":[],\"usage\":{"
            + "\"prompt_tokens\":10,\"completion_tokens\":5,\"prompt_tokens_details\":{\"cached_tokens\":4}}}\n\n"
            + "data: [DONE]\n\n"
    }
}
