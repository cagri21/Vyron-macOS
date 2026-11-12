import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOpenAIResponsesTokenCountTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testExactCountRetainsEverySchemaAndSelectedOutputWithoutReportingGenerationUsageForCounting() async throws {
        let guidance = String(repeating: "Retain these project rules.\n", count: 1_000)
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            if request.url?.path == "/v1/responses/input_tokens" {
                let body = try VyronResponsesTestSupport.body(request)
                XCTAssertEqual(body["model"] as? String, VyronResponsesTestSupport.model)
                XCTAssertNil(body["max_output_tokens"])
                let input = try XCTUnwrap(body["input"] as? [[String: Any]])
                XCTAssertEqual(input.first?["content"] as? String, guidance)
                return VyronResponsesTestResponse(body: #"{"object":"response.input_tokens","input_tokens":8000}"#)
            }
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(body["max_output_tokens"] as? Int, 4_096)
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.textOutput("The complete result.")
            ]))
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        let result = try await step(using: client(recorder: recorder), content: guidance)
        XCTAssertEqual(result.message.content, "The complete result.")
        let requests = await VyronResponsesTestURLProtocol.state.requests
        let countRequest = try XCTUnwrap(requests.first { $0.url?.path == "/v1/responses/input_tokens" })
        let countBody = try VyronResponsesTestSupport.body(countRequest)
        let generation = try XCTUnwrap(requests.last)
        let generationBody = try VyronResponsesTestSupport.body(generation)
        for key in ["model", "input", "tools"] {
            XCTAssertEqual(
                try VyronResponsesTestSupport.json([key: countBody[key] ?? NSNull()]),
                try VyronResponsesTestSupport.json([key: generationBody[key] ?? NSNull()])
            )
        }
        let tools = try XCTUnwrap(generationBody["tools"] as? [[String: Any]])
        XCTAssertTrue(tools.contains { $0["name"] as? String == "large_fixture" })
        let events = await recorder.events
        XCTAssertEqual(events.count, 2, "Only the capability probe and generation have generation usage")
    }

    func testOversizedAndInvalidTokenCountsNeverStartGeneration() async throws {
        let counts = [
            #"{"object":"response.input_tokens","input_tokens":32768}"#,
            #"{"object":"response.input_tokens","input_tokens":-1}"#,
            #"{"object":"response.input_tokens"}"#,
            #"{"object":"unexpected","input_tokens":100}"#,
            #"{"object":"response.input_tokens","input_tokens":1.5}"#,
            "{malformed"
        ]
        for count in counts {
            await VyronResponsesTestURLProtocol.state.reset { request, _ in
                if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
                XCTAssertEqual(request.url?.path, "/v1/responses/input_tokens")
                return VyronResponsesTestResponse(body: count)
            }
            do {
                _ = try await step(using: client())
                XCTFail("An oversized or invalid token count must not allow generation")
            } catch {
                XCTAssertTrue(error is ModelProviderError || error as? DevelopmentAgentError == .contextBudget)
            }
            let requests = await VyronResponsesTestURLProtocol.state.requests
            XCTAssertEqual(requests.filter { $0.url?.path == "/v1/responses/input_tokens" }.count, 1)
            XCTAssertEqual(try generationRequests(requests).count, 0)
        }
    }

    func testCounterHTTPFailureDoesNotGenerateOrInventTokenUsage() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            return VyronResponsesTestResponse(body: "server details must stay private", statusCode: 503)
        }
        let recorder = VyronOpenAIUsageTestRecorder()
        do {
            _ = try await step(using: client(recorder: recorder))
            XCTFail("A failed count cannot authorize generation")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .http(503))
        }
        let events = await recorder.events
        XCTAssertEqual(events.count, 1, "Only the capability probe was generated")
    }

    func testOversizedAuthoritativeInputStillFailsBeforeTokenCounting() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            XCTFail("Oversized authoritative content must not be sent to counting or generation")
            return VyronResponsesTestResponse(body: "{}")
        }
        do {
            _ = try await client().developmentStep(
                model: VyronResponsesTestSupport.model,
                messages: [DevelopmentMessage(role: "user", content: String(repeating: "x", count: 131_072))],
                mode: .plan
            )
            XCTFail("The expanded message byte limit must remain enforced")
        } catch {
            XCTAssertEqual(error as? DevelopmentAgentError, .contextBudget)
        }
        let requests = await VyronResponsesTestURLProtocol.state.requests
        XCTAssertFalse(requests.contains { $0.url?.path == "/v1/responses/input_tokens" })
    }

    func testCancellingTokenCountingPreventsGeneration() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            return VyronResponsesTestResponse(body: "{", holdOpen: true)
        }
        let provider = try client()
        let operation = Task { try await step(using: provider) }
        for _ in 0..<1_000 {
            let requests = await VyronResponsesTestURLProtocol.state.requests
            if requests.contains(where: { $0.url?.path == "/v1/responses/input_tokens" }) { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        operation.cancel()
        do {
            _ = try await operation.value
            XCTFail("Cancellation must propagate")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let requests = await VyronResponsesTestURLProtocol.state.requests
        XCTAssertEqual(try generationRequests(requests).count, 0)
    }

    private func step(
        using client: VyronOpenAIResponsesClient,
        content: String = "Inspect this project."
    ) async throws -> DevelopmentStep {
        try await client.developmentStep(
            model: VyronResponsesTestSupport.model,
            messages: [DevelopmentMessage(role: "user", content: content)],
            effort: .balanced,
            mode: .plan,
            externalTools: [DevelopmentExternalTool(
                name: "large_fixture", description: String(repeating: "Schema documentation. ", count: 2_000),
                inputSchema: ["type": .string("object")], isReadOnly: true
            )]
        )
    }

    private func client(recorder: VyronOpenAIUsageTestRecorder? = nil) throws -> VyronOpenAIResponsesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        return try VyronOpenAIResponsesClient(
            connection: VyronResponsesTestSupport.profile(settings: ModelSettings(
                contextTokens: 32_768, maxOutputTokens: 4_096
            )),
            configuration: configuration,
            usageHandler: { event in await recorder?.append(event) }
        )
    }

    private func generationRequests(_ requests: [URLRequest]) throws -> [URLRequest] {
        try requests.filter { request in
            guard request.url?.path == "/v1/responses" else { return false }
            return try VyronResponsesTestSupport.body(request)["tool_choice"] == nil
        }
    }
}
