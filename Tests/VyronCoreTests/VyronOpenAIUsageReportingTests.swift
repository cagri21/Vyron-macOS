import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOpenAIUsageReportingTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testCompletedStreamReportsActualModelUsageExactlyOnce() async throws {
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(body: Self.stream(status: "completed", usage: Self.usage))
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let profile = VyronResponsesTestSupport.profile()
        let client = try client(profile, recorder: recorder)
        let before = Date()
        let answer = try await client.chat(
            model: profile.selectedModel, messages: [ChatMessage(role: "user", content: "Hi")]
        ) { _ in }
        XCTAssertEqual(answer, "Hello")
        let events = await recorder.events
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.connectionID, profile.id)
        XCTAssertGreaterThanOrEqual(event.startedAt, before)
        XCTAssertEqual(event.observation.responseID, "resp_usage")
        XCTAssertEqual(event.observation.model, "gpt-6.1-sol-2026-10-07")
        XCTAssertEqual(event.observation.result, .measured(.init(
            inputTokens: 100, outputTokens: 20,
            inputDetails: .init(cachedTokens: 40, cacheWrite30mTokens: 0, cacheWrite12hTokens: 0)
        )))
    }

    func testIncompleteStreamReportsChargedUsageBeforeThrowing() async throws {
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(body: Self.stream(status: "incomplete", usage: Self.usage))
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let client = try client(VyronResponsesTestSupport.profile(), recorder: recorder)
        do {
            _ = try await client.chat(
                model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hi")]
            ) { _ in }
            XCTFail("Expected incomplete output failure")
        } catch { XCTAssertTrue(error is ModelProviderError) }
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        guard case .measured = events.first?.observation.result else { return XCTFail("Lost charged usage") }
    }

    func testMalformedUsageNeverBreaksAValidVisibleAnswer() async throws {
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(body: Self.stream(status: "completed", usage: #"{"input_tokens":-2}"#))
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let client = try client(VyronResponsesTestSupport.profile(), recorder: recorder)
        let result = try await client.chat(
            model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hi")]
        ) { _ in }
        XCTAssertEqual(result, "Hello")
        let events = await recorder.events
        XCTAssertEqual(events.first?.observation.result, .unavailable(.invalidUsage))
    }

    func testToolProbeAndEveryDevelopmentStepEachReportUsage() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            return VyronResponsesTestResponse(body: """
            {"id":"resp_development","status":"completed","model":"gpt-6.1-sol","usage":\(Self.usage),
             "output":[{"type":"message","role":"assistant","status":"completed",
               "content":[{"type":"output_text","text":"Plan ready."}]}]}
            """)
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let client = try client(VyronResponsesTestSupport.profile(), recorder: recorder)
        _ = try await client.developmentStep(
            model: "gpt-6.1-sol", messages: [DevelopmentMessage(role: "user", content: "Plan")], mode: .plan
        )
        let events = await recorder.events
        XCTAssertEqual(events.count, 2, "Tool verification and the inference are separate billable requests")
        XCTAssertNotEqual(events[0].requestID, events[1].requestID)
        XCTAssertEqual(events[0].observation.result, .unavailable(.missingUsage), "Probe fixture omits usage")
        guard case .measured = events[1].observation.result else { return XCTFail("Lost development usage") }
    }

    func testTruncatedStreamMarksUnknownCostAndHTTPRejectionDoesNotClaimATokenCharge() async throws {
        for (status, expectedCount) in [(200, 1), (403, 0), (500, 1)] {
            await VyronResponsesTestURLProtocol.state.reset { _, _ in
                VyronResponsesTestResponse(body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Partial\"}\n\n", statusCode: status)
            }
            let recorder = VyronOpenAIUsageTestRecorder()
            let client = try client(VyronResponsesTestSupport.profile(), recorder: recorder)
            do {
                _ = try await client.chat(
                    model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hi")]
                ) { _ in }
                XCTFail("Expected transport failure")
            } catch { XCTAssertTrue(error is ModelProviderError) }
            let events = await recorder.events
            XCTAssertEqual(events.count, expectedCount)
            if expectedCount == 1 { XCTAssertEqual(events.first?.observation.result, .unavailable(.interrupted)) }
        }
    }

    func testFailedDevelopmentOutputRetainsBillableUsage() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            return VyronResponsesTestResponse(body: """
            {"id":"resp_failed_output","status":"incomplete","usage":\(Self.usage),"output":[]}
            """)
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let client = try client(VyronResponsesTestSupport.profile(), recorder: recorder)
        do {
            _ = try await client.developmentStep(
                model: "gpt-6.1-sol", messages: [DevelopmentMessage(role: "user", content: "Plan")], mode: .plan
            )
            XCTFail("Incomplete development must fail")
        } catch { XCTAssertTrue(error is ModelProviderError) }
        let events = await recorder.events
        XCTAssertEqual(events.count, 2)
        guard case .measured = events.last?.observation.result else { return XCTFail("Lost incomplete usage") }
    }

    func testCancellingAnActiveStreamReportsUnknownCostExactlyOnce() async throws {
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(
                body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Started\"}\n\n",
                holdOpen: true
            )
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let client = try client(VyronResponsesTestSupport.profile(), recorder: recorder)
        let tokens = VyronResponsesTestTokens()
        let task = Task {
            try await client.chat(
                model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hi")]
            ) { token in Task { await tokens.append(token) } }
        }
        for _ in 0..<1000 {
            if await tokens.values.contains("Started") { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must remain cancellation") } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let events = await recorder.events
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.observation.result, .unavailable(.interrupted))
    }

    private func client(
        _ profile: ModelConnectionProfile,
        recorder: VyronOpenAIUsageTestRecorder
    ) throws -> VyronOpenAIResponsesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        return try VyronOpenAIResponsesClient(
            connection: profile, transport: .init(configuration: configuration),
            usageHandler: { await recorder.append($0) }
        )
    }

    nonisolated private static let usage = #"{"input_tokens":100,"output_tokens":20,"input_tokens_details":{"cached_tokens":40}}"#

    nonisolated private static func stream(status: String, usage: String) -> String {
        "data: {\"type\":\"response.\(status)\",\"response\":{\"id\":\"resp_usage\","
            + "\"model\":\"gpt-6.1-sol-2026-10-07\",\"status\":\"\(status)\",\"usage\":\(usage),"
            + "\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"status\":\"completed\","
            + "\"content\":[{\"type\":\"output_text\",\"text\":\"Hello\"}]}]}}\n\n"
    }
}
