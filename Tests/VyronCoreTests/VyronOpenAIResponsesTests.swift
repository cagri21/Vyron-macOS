import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOpenAIResponsesTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testOfficialGPT6SelectionsUseResponsesWithoutReroutingOtherConnections() throws {
        for model in [
            "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-6.1-sol", "gpt-6.1-terra",
            "gpt-6.1-sol-2026-10-07", "gpt-6.2-astra", "gpt-6.2-sol", "gpt-6.2-sol-2026-11-18"
        ] {
            var profile = VyronResponsesTestSupport.profile()
            profile.selectedModel = model
            XCTAssertTrue(try profile.makeProvider() is VyronOpenAIResponsesClient, model)
        }
        for model in [
            "gpt-4.1", "gpt-5.5", "gpt-6.1-sol-proxy", "gpt-6.1-sol-2026-10-07-extra",
            "gpt-6.2-astra-proxy", "gpt-6.2-sol-2026-11-18-extra"
        ] {
            var profile = VyronResponsesTestSupport.profile()
            profile.selectedModel = model
            XCTAssertTrue(try profile.makeProvider() is OpenAICompatibleClient, model)
        }
        for endpoint in [
            "https://models.example.test/v1", "https://api.openai.com.example.test/v1",
            "https://api.openai.com/proxy/v1", "https://api.openai.com:8443/v1"
        ] {
            var profile = VyronResponsesTestSupport.profile()
            profile.endpoint = endpoint
            XCTAssertTrue(try profile.makeProvider() is OpenAICompatibleClient, endpoint)
            profile.selectedModel = "gpt-6.2-sol"
            XCTAssertTrue(try profile.makeProvider() is OpenAICompatibleClient, endpoint)
        }
        var profile = VyronResponsesTestSupport.profile()
        profile.kind = .ollama
        XCTAssertTrue(try profile.makeProvider() is OllamaClient)
    }

    func testDevelopmentUsesResponsesToolSchemaAndSavedOutputBudget() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            XCTAssertEqual(request.url?.path, "/v1/responses")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer offline-test-key")
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(body["model"] as? String, "gpt-6.1-sol")
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual(body["store"] as? Bool, false)
            XCTAssertEqual(body["include"] as? [String], ["reasoning.encrypted_content"])
            XCTAssertEqual(body["max_output_tokens"] as? Int, 4_096)
            XCTAssertNil(body["reasoning"], "Normal requests preserve the provider's reasoning default")
            XCTAssertNil(body["messages"])
            XCTAssertNil(body["max_tokens"])
            XCTAssertNil(body["temperature"])
            XCTAssertNil(body["top_p"])
            XCTAssertNil(body["previous_response_id"])
            let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
            let search = try XCTUnwrap(tools.first { $0["name"] as? String == "search" })
            XCTAssertEqual(search["type"] as? String, "function")
            XCTAssertEqual(search["strict"] as? Bool, false)
            XCTAssertNil(search["function"])
            let parameters = try XCTUnwrap(search["parameters"] as? [String: Any])
            XCTAssertEqual(parameters["required"] as? [String], ["query"])
            XCTAssertNotNil((parameters["properties"] as? [String: Any])?["limit"])
            XCTAssertFalse(tools.contains { $0["name"] as? String == "write_file" })
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.textOutput("Plan ready.")
            ]))
        }
        let client = try VyronResponsesTestSupport.client(settings: ModelSettings(
            contextTokens: 32_768, maxOutputTokens: 4_096
        ))
        let step = try await client.developmentStep(
            model: "gpt-6.1-sol", messages: [DevelopmentMessage(role: "user", content: "Plan a fix")],
            effort: .balanced, mode: .plan
        )
        XCTAssertEqual(step.message.content, "Plan ready.")
        XCTAssertEqual(step.message.continuation?.source, "openai.responses.v1")
        XCTAssertEqual(step.message.continuation?.model, "gpt-6.1-sol")
    }

    func testToolProbeUsesForcedResponsesFunctionAndRetainsExactNonce() async throws {
        await VyronResponsesTestURLProtocol.state.reset({ request, _ in
            if request.url?.path == "/v1/models" {
                return VyronResponsesTestResponse(body: #"{"data":[{"id":"gpt-6.1-sol"}]}"#)
            }
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(request.url?.path, "/v1/responses")
            XCTAssertEqual((body["tool_choice"] as? [String: String])?["name"], "vyron_check_tools")
            XCTAssertEqual((body["tool_choice"] as? [String: String])?["type"], "function")
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            let encoded = try VyronResponsesTestSupport.json(input)
            let range = try XCTUnwrap(encoded.range(of: "nonce "))
            let nonce = String(encoded[range.upperBound...].prefix(36))
            XCTAssertNotNil(UUID(uuidString: nonce))
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.toolOutput(
                    "probe-call", name: "vyron_check_tools",
                    arguments: try VyronResponsesTestSupport.json(["nonce": nonce])
                )
            ]))
        }, automaticallyAnswerToolProbe: false)
        let client = try VyronResponsesTestSupport.client()
        let selected = try await client.developmentModel(
            model: "gpt-6.1-sol", automaticModelSelection: false, effort: .balanced
        )
        XCTAssertTrue(selected.capabilities?.contains("tools") == true)
        let requestCount = await VyronResponsesTestURLProtocol.state.requests.count
        XCTAssertEqual(requestCount, 2)
    }

    func testStatelessToolReplaySurvivesCodableAndAnInterleavedConversation() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertNil(body["previous_response_id"])
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            if let result = input.first(where: { $0["type"] as? String == "function_call_output" }) {
                XCTAssertEqual(result["call_id"] as? String, "call-exact")
                XCTAssertEqual(result["output"] as? String, "README.md")
                XCTAssertEqual(input.filter { $0["type"] as? String == "function_call" }.count, 1)
                XCTAssertEqual(input.first { $0["type"] as? String == "reasoning" }?["id"] as? String, "rs_first")
                XCTAssertTrue(input.first { $0["type"] as? String == "reasoning" }?["status"] is NSNull)
                XCTAssertEqual(input.first { $0["id"] as? String == "msg_test" }?["phase"] as? String, "commentary")
                XCTAssertEqual(
                    input.first { $0["type"] as? String == "reasoning" }?["encrypted_content"] as? String,
                    "opaque-rs_first"
                )
                return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                    VyronResponsesTestSupport.textOutput("Read complete.")
                ]))
            }
            if try VyronResponsesTestSupport.json(input).contains("Other conversation") {
                XCTAssertFalse(input.contains { $0["type"] as? String == "reasoning" })
                XCTAssertFalse(input.contains { $0["type"] as? String == "function_call" })
                return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                    VyronResponsesTestSupport.textOutput("Other answer.")
                ]))
            }
            var commentary = VyronResponsesTestSupport.textOutput("Inspecting.")
            commentary["phase"] = "commentary"
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.reasoning("rs_first"),
                commentary,
                VyronResponsesTestSupport.toolOutput("call-exact", arguments: #"{"limit":10}"#)
            ]))
        }
        let client = try VyronResponsesTestSupport.client()
        let initial = [DevelopmentMessage(role: "user", content: "Inspect")]
        let first = try await client.developmentStep(model: "gpt-6.1-sol", messages: initial, mode: .plan)
        let stored = try JSONDecoder().decode(
            DevelopmentMessage.self, from: JSONEncoder().encode(first.message)
        )
        XCTAssertEqual(stored.toolCalls?.first?.id, "call-exact")
        XCTAssertEqual(stored, first.message)
        _ = try await client.developmentStep(
            model: "gpt-6.1-sol", messages: [DevelopmentMessage(role: "user", content: "Other conversation")],
            mode: .plan
        )
        let restoredClient = try VyronResponsesTestSupport.client()
        let next = try await restoredClient.developmentStep(
            model: "gpt-6.1-sol", messages: initial + [stored, DevelopmentMessage(
                role: "tool", content: "README.md", toolName: "list_files", toolCallID: "call-exact"
            )], mode: .plan
        )
        XCTAssertEqual(next.message.content, "Read complete.")
    }
}
