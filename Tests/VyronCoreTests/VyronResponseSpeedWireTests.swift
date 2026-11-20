import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronResponseSpeedWireTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testResponsesChatSelectsTheRequestedTierAndKeepsItsModelAndEffortBudget() async throws {
        for speed in [nil, VyronResponseSpeed.standard, .fast] {
            let expected = speed == .fast ? "fast" : "default"
            await VyronResponsesTestURLProtocol.state.reset { request, _ in
                let body = try VyronResponsesTestSupport.body(request)
                XCTAssertEqual(body["model"] as? String, "gpt-6.1-sol")
                XCTAssertEqual(body["service_tier"] as? String, expected)
                XCTAssertEqual(body["max_output_tokens"] as? Int, 1_024)
                XCTAssertEqual(body["store"] as? Bool, false)
                return try VyronResponsesTestResponse(body: VyronResponsesTestSupport.stream("Ready"))
            }
            var settings = ModelSettings(maxOutputTokens: 1_024)
            settings.responseSpeed = speed
            let client = try VyronResponsesTestSupport.client(settings: settings)
            let answer = try await client.chat(
                model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hello")]
            ) { _ in }
            XCTAssertEqual(answer, "Ready")
        }
    }

    func testWorkAndItsToolProbeBothUseFastWithoutAddingCommands() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(body["service_tier"] as? String, "fast")
            XCTAssertEqual(body["model"] as? String, "gpt-6.1-sol")
            if (body["tool_choice"] as? [String: Any])?["name"] as? String == "vyron_check_tools" {
                let messages = try XCTUnwrap(body["input"] as? [[String: Any]])
                let text = try XCTUnwrap(messages.first?["content"] as? String)
                let nonce = try XCTUnwrap(text.components(separatedBy: "nonce ").last?.split(separator: ".").first)
                let arguments = try VyronResponsesTestSupport.json(["nonce": String(nonce)])
                return try VyronResponsesTestResponse(body: VyronResponsesTestSupport.completion([
                    VyronResponsesTestSupport.toolOutput("probe", name: "vyron_check_tools", arguments: arguments)
                ]))
            }
            return try VyronResponsesTestResponse(body: VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.textOutput("Read-only plan")
            ]))
        }
        var settings = ModelSettings()
        settings.responseSpeed = .fast
        let client = try VyronResponsesTestSupport.client(settings: settings)
        let step = try await client.developmentStep(
            model: "gpt-6.1-sol", messages: [DevelopmentMessage(role: "user", content: "Plan")],
            effort: .maximum, mode: .plan
        )
        XCTAssertEqual(step.message.content, "Read-only plan")
        XCTAssertTrue(step.message.toolCalls?.isEmpty != false)
    }

    func testLegacyOpenAIChatSelectsFastWithoutRequiringABalanceObserver() async throws {
        let stream = Self.compatibleStream
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(body["service_tier"] as? String, "fast")
            XCTAssertEqual(body["model"] as? String, "gpt-5.3-codex")
            return VyronResponsesTestResponse(body: stream)
        }
        var profile = VyronResponsesTestSupport.profile()
        profile.selectedModel = "gpt-5.3-codex"
        profile.settings.responseSpeed = .fast
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        let client = try OpenAICompatibleClient(connection: profile, configuration: configuration)
        let answer = try await client.chat(model: profile.selectedModel, messages: [ChatMessage(role: "user", content: "Hi")]) {
            _ in
        }
        XCTAssertEqual(answer, "Ready")
    }

    func testOtherProvidersNeverReceiveOpenAIFastOrStandardTierFields() async throws {
        let stream = Self.compatibleStream
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertNil(body["service_tier"])
            return VyronResponsesTestResponse(body: stream)
        }
        var profile = VyronResponsesTestSupport.profile()
        profile.endpoint = "https://models.example.test/v1"
        profile.settings.responseSpeed = .fast
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        let client = try OpenAICompatibleClient(connection: profile, configuration: configuration)
        _ = try await client.chat(model: profile.selectedModel, messages: [ChatMessage(role: "user", content: "Hi")]) { _ in }
    }

    func testFastEstimateUsesTheReturnedTierAndNeverAssumesStandardWhenTheTierIsMissing() async throws {
        for returnedTier in ["priority", "default", "missing"] {
            await VyronResponsesTestURLProtocol.state.reset { _, _ in
                var response: [String: Any] = [
                    "id": "speed_response", "model": "gpt-6.1-sol", "status": "completed",
                    "output": [VyronResponsesTestSupport.textOutput("Ready")],
                    "usage": ["input_tokens": 1_000, "output_tokens": 500]
                ]
                if returnedTier != "missing" { response["service_tier"] = returnedTier }
                let event = try VyronResponsesTestSupport.json(["type": "response.completed", "response": response])
                return VyronResponsesTestResponse(body: "data: " + event + "\n\n")
            }
            var profile = VyronResponsesTestSupport.profile()
            profile.settings.responseSpeed = .fast
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
            let recorder = VyronOpenAIUsageTestRecorder()
            let client = try VyronOpenAIResponsesClient(
                connection: profile, transport: .init(configuration: configuration),
                usageHandler: { await recorder.append($0) }
            )
            _ = try await client.chat(model: profile.selectedModel, messages: [ChatMessage(role: "user", content: "Hi")]) {
                _ in
            }
            let events = await recorder.events
            let event = try XCTUnwrap(events.first)
            XCTAssertEqual(events.count, 1)
            if returnedTier == "missing" {
                XCTAssertNil(VyronOpenAICostEstimator.cost(for: event.observation))
            } else {
                let expected = Decimal(string: returnedTier == "priority" ? "0.014" : "0.007")
                XCTAssertEqual(VyronOpenAICostEstimator.cost(for: event.observation), expected)
            }
        }
    }

    private static let compatibleStream = """
    data: {"choices":[{"delta":{"content":"Ready"},"finish_reason":"stop"}]}

    data: [DONE]


    """
}
