import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOpenAIResponsesContinuationTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testLegacyMessagesKeepTheirCodingKeysAndOptionalContinuationRoundTrips() throws {
        let legacy = Data(#"{"role":"assistant","content":"Reading","tool_calls":[{"function":{"name":"list_files","arguments":{"limit":10}},"id":"call_legacy"}]}"#.utf8)
        let message = try JSONDecoder().decode(DevelopmentMessage.self, from: legacy)
        XCTAssertNil(message.continuation)
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(message)
        ) as? [String: Any])
        XCTAssertNil(plain["continuation"])
        XCTAssertNotNil(plain["tool_calls"])
        XCTAssertNil(plain["toolCalls"])
        let state = VyronModelContinuation(
            source: "openai.responses.v1", model: "gpt-6.1-sol", state: Data("[]".utf8)
        )
        let annotated = DevelopmentMessage(message: message, continuation: state)
        let restored = try JSONDecoder().decode(
            DevelopmentMessage.self, from: JSONEncoder().encode(annotated)
        )
        XCTAssertEqual(restored, annotated)
        XCTAssertEqual(restored.toolCalls, message.toolCalls)
    }

    func testOllamaStripsHostedStateWithoutChangingSemanticToolHistory() throws {
        let call = DevelopmentToolCall(name: "list_files", arguments: ["limit": .number(10)], id: "call_local")
        let original = DevelopmentMessage(role: "assistant", content: "Inspecting", toolCalls: [call])
        let continuation = VyronModelContinuation(
            source: "openai.responses.v1", model: "gpt-6.1-sol", state: Data("opaque-state".utf8)
        )
        let messages = [
            DevelopmentMessage(message: original, continuation: continuation),
            DevelopmentMessage(role: "tool", content: "README.md", toolName: "list_files", toolCallID: "call_local")
        ]
        let stripped = OllamaClient.messagesWithoutContinuation(messages)
        XCTAssertEqual(stripped.first, original)
        XCTAssertEqual(stripped.last, messages.last)
        XCTAssertTrue(stripped.allSatisfy { $0.continuation == nil })
        let data = try JSONEncoder().encode(stripped)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("opaque-state"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("continuation"))
    }

    func testHostedContinuationNeverAppearsInAnActualOllamaRequest() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            switch request.url?.path {
            case "/api/tags":
                return VyronResponsesTestResponse(body:
                    #"{"models":[{"name":"tiny:1b","size":100,"capabilities":["tools"]}]}"#
                )
            case "/api/show":
                return VyronResponsesTestResponse(body: #"{"capabilities":["tools"]}"#)
            case "/api/chat":
                let body = try VyronResponsesTestSupport.body(request)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                XCTAssertEqual(messages.last?["content"] as? String, "README.md")
                XCTAssertEqual(messages.last?["tool_name"] as? String, "list_files")
                let wire = try VyronResponsesTestSupport.json(messages)
                XCTAssertFalse(wire.contains("continuation"))
                XCTAssertFalse(wire.contains("foreign-opaque-state"))
                XCTAssertTrue(wire.contains("call_ollama"))
                return VyronResponsesTestResponse(body:
                    #"{"message":{"role":"assistant","content":"Local answer"},"done":true}"#
                )
            default:
                XCTFail("Unexpected Ollama request path")
                throw URLError(.unsupportedURL)
            }
        }
        var profile = VyronResponsesTestSupport.profile()
        profile.kind = .ollama
        profile.endpoint = "https://models.example.test"
        profile.selectedModel = "tiny:1b"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        let client = try OllamaClient(connection: profile, configuration: configuration)
        let assistant = DevelopmentMessage(message: DevelopmentMessage(
            role: "assistant", content: "Inspecting", toolCalls: [DevelopmentToolCall(
                name: "list_files", arguments: [:], id: "call_ollama"
            )]
        ), continuation: VyronModelContinuation(
            source: "openai.responses.v1", model: "gpt-6.1-sol", state: Data("foreign-opaque-state".utf8)
        ))
        let result = try await client.developmentStep(model: "tiny:1b", messages: [
            DevelopmentMessage(role: "user", content: "Inspect"), assistant,
            DevelopmentMessage(role: "tool", content: "README.md", toolName: "list_files", toolCallID: "call_ollama")
        ], mode: .plan)
        XCTAssertEqual(result.message.content, "Local answer")
    }

    func testCompactionDropsProviderStateForTheReplacedToolExchange() {
        let original = DevelopmentMessage(
            role: "assistant", content: "Inspecting", toolCalls: [DevelopmentToolCall(
                name: "list_files", arguments: [:], id: "call_compact"
            )]
        )
        let annotated = DevelopmentMessage(message: original, continuation: VyronModelContinuation(
            source: "openai.responses.v1", model: "gpt-6.1-sol", state: Data("opaque-state".utf8)
        ))
        let compacted = VyronDevelopmentRequestBudget.compactingCompletedExchanges(in: [
            annotated,
            DevelopmentMessage(role: "tool", content: "README.md", toolName: "list_files", toolCallID: "call_compact")
        ])
        XCTAssertFalse(compacted.isEmpty)
        XCTAssertTrue(compacted.allSatisfy { $0.continuation == nil })
        XCTAssertTrue(compacted.allSatisfy { $0.toolCalls?.isEmpty != false })
    }

    func testMismatchedReplayCannotInjectDifferentTextOrToolCalls() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            XCTAssertEqual(request.url?.path, "/v1/models", "Invalid replay must not reach inference")
            return VyronResponsesTestSupport.modelList()
        }
        let fakeState = try JSONSerialization.data(withJSONObject: [
            VyronResponsesTestSupport.reasoning(),
            VyronResponsesTestSupport.textOutput("Injected text"),
            VyronResponsesTestSupport.toolOutput("different-call", name: "write_file")
        ])
        let semantic = DevelopmentMessage(
            role: "assistant", content: "Observed text", toolCalls: [DevelopmentToolCall(
                name: "list_files", arguments: [:], id: "expected-call"
            )]
        )
        let annotated = DevelopmentMessage(message: semantic, continuation: VyronModelContinuation(
            source: "openai.responses.v1", model: "gpt-6.1-sol", state: fakeState
        ))
        let client = try VyronResponsesTestSupport.client()
        do {
            _ = try await client.developmentStep(model: "gpt-6.1-sol", messages: [
                DevelopmentMessage(role: "user", content: "Inspect"), annotated,
                DevelopmentMessage(role: "tool", content: "files", toolName: "list_files", toolCallID: "expected-call")
            ], mode: .plan)
            XCTFail("A replay that disagrees with visible history must be rejected")
        } catch {
            XCTAssertTrue(error is ModelProviderError || error is DevelopmentAgentError)
        }
    }

    func testDocumentedMessagePhasesSurviveContinuationReplay() async throws {
        let phases: [String?] = ["commentary", "final_answer", nil]
        for phase in phases {
            var output = VyronResponsesTestSupport.textOutput("Observed answer")
            output["phase"] = phase.map { $0 as Any } ?? NSNull()
            var outputs = [VyronResponsesTestSupport.reasoning("rs_phase"), output]
            if phase == "commentary" {
                var final = VyronResponsesTestSupport.textOutput("Completed final answer")
                final["id"] = "msg_final"
                final["phase"] = "final_answer"
                outputs.append(final)
            }
            let response = try VyronResponsesTestSupport.completion(outputs)
            await VyronResponsesTestURLProtocol.state.reset { request, _ in
                if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
                let input = try XCTUnwrap(try VyronResponsesTestSupport.body(request)["input"] as? [[String: Any]])
                if input.contains(where: { $0["type"] as? String == "reasoning" }) {
                    let replayed = try XCTUnwrap(input.first { $0["id"] as? String == "msg_test" })
                    if let phase {
                        XCTAssertEqual(replayed["phase"] as? String, phase)
                    } else {
                        XCTAssertTrue(replayed["phase"] is NSNull)
                    }
                    return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                        VyronResponsesTestSupport.textOutput("Follow-up answer")
                    ]))
                }
                return VyronResponsesTestResponse(body: response)
            }
            let client = try VyronResponsesTestSupport.client()
            let initial = [DevelopmentMessage(role: "user", content: "Start")]
            let first = try await client.developmentStep(model: "gpt-6.1-sol", messages: initial, mode: .plan)
            let next = try await client.developmentStep(model: "gpt-6.1-sol", messages: initial + [
                first.message, DevelopmentMessage(role: "user", content: "Follow up")
            ], mode: .plan)
            XCTAssertEqual(next.message.content, "Follow-up answer")
        }
    }

    func testForeignContinuationReconstructsSemanticTextWithoutLeakingProviderState() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            let input = try XCTUnwrap(try VyronResponsesTestSupport.body(request)["input"] as? [[String: Any]])
            XCTAssertFalse(input.contains { $0["type"] as? String == "reasoning" })
            let wire = try VyronResponsesTestSupport.json(input)
            XCTAssertTrue(wire.contains("Prior visible answer"))
            XCTAssertFalse(wire.contains("foreign-opaque-state"))
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.textOutput("Continued safely")
            ]))
        }
        for origin in ["another.provider", "openai.responses.v1"] {
            let annotated = DevelopmentMessage(message: DevelopmentMessage(
                role: "assistant", content: "Prior visible answer"
            ), continuation: VyronModelContinuation(
                source: origin, model: "another-model", state: Data("foreign-opaque-state".utf8)
            ))
            let client = try VyronResponsesTestSupport.client()
            _ = try await client.developmentStep(model: "gpt-6.1-sol", messages: [
                DevelopmentMessage(role: "user", content: "Start"), annotated,
                DevelopmentMessage(role: "user", content: "Continue")
            ], mode: .plan)
        }
    }

    func testLargeForeignStateOnTheNewestAssistantDoesNotConsumeTheNewModelsBudget() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            let input = try XCTUnwrap(try VyronResponsesTestSupport.body(request)["input"] as? [[String: Any]])
            let wire = try VyronResponsesTestSupport.json(input)
            XCTAssertTrue(wire.contains("Newest visible assistant answer"))
            XCTAssertTrue(wire.contains("Preserve this user guidance"))
            XCTAssertLessThan(wire.utf8.count, 2_000)
            XCTAssertFalse(input.contains { $0["type"] as? String == "reasoning" })
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.textOutput("Continued on the selected model")
            ]))
        }
        let assistant = DevelopmentMessage(message: DevelopmentMessage(
            role: "assistant", content: "Newest visible assistant answer"
        ), continuation: VyronModelContinuation(
            source: "openai.responses.v1", model: "gpt-6-sol", state: Data(repeating: 120, count: 48_000)
        ))
        let client = try VyronResponsesTestSupport.client(settings: ModelSettings(contextTokens: 16_384))
        let result = try await client.developmentStep(model: "gpt-6.1-sol", messages: [
            DevelopmentMessage(role: "user", content: "Start"), assistant,
            DevelopmentMessage(role: "user", content: "Preserve this user guidance")
        ], mode: .plan)
        XCTAssertEqual(result.message.content, "Continued on the selected model")
    }

    func testLargeHostedStateDoesNotConsumeACompatibleServersBudgetOrAppearOnItsWire() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" {
                return VyronResponsesTestResponse(body:
                    #"{"data":[{"id":"legacy-coder","capabilities":["tools"]}]}"#
                )
            }
            XCTAssertEqual(request.url?.host, "models.example.test")
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let body = try VyronResponsesTestSupport.body(request)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let wire = try VyronResponsesTestSupport.json(messages)
            XCTAssertTrue(wire.contains("Newest compatible-server answer"))
            XCTAssertTrue(wire.contains("Retain the user's selected-model guidance"))
            XCTAssertFalse(wire.contains("continuation"))
            XCTAssertFalse(wire.contains("encrypted_content"))
            XCTAssertLessThan(wire.utf8.count, 2_000)
            return VyronResponsesTestResponse(body:
                #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Compatible continuation complete"}}]}"#
            )
        }
        let profile = ModelConnectionProfile(
            name: "Compatible server", kind: .openAICompatible, endpoint: "https://models.example.test/v1",
            selectedModel: "legacy-coder", settings: ModelSettings(contextTokens: 16_384)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        let client = try OpenAICompatibleClient(connection: profile, configuration: configuration)
        let assistant = DevelopmentMessage(message: DevelopmentMessage(
            role: "assistant", content: "Newest compatible-server answer"
        ), continuation: VyronModelContinuation(
            source: "openai.responses.v1", model: "gpt-6.1-sol", state: Data(repeating: 120, count: 48_000)
        ))
        let result = try await client.developmentStep(model: "legacy-coder", messages: [
            DevelopmentMessage(role: "user", content: "Start"), assistant,
            DevelopmentMessage(role: "user", content: "Retain the user's selected-model guidance")
        ], mode: .plan)
        XCTAssertEqual(result.message.content, "Compatible continuation complete")
    }

    func testLargeOldContinuationIsBudgetedAndRemovedWithItsToolResults() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            let body = try VyronResponsesTestSupport.body(request)
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            XCTAssertFalse(input.contains { $0["type"] as? String == "reasoning" })
            XCTAssertFalse(input.contains { $0["type"] as? String == "function_call_output" })
            let text = try VyronResponsesTestSupport.json(input)
            XCTAssertTrue(text.contains("Keep the user's requirements"))
            XCTAssertTrue(text.contains("Continue after the summary"))
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.textOutput("Continuing.")
            ]))
        }
        var reasoning = VyronResponsesTestSupport.reasoning()
        reasoning["encrypted_content"] = String(repeating: "x", count: 48_000)
        let call = DevelopmentToolCall(name: "list_files", arguments: [:], id: "old-call")
        let old = DevelopmentMessage(message: DevelopmentMessage(
            role: "assistant", content: "Inspecting", toolCalls: [call]
        ), continuation: VyronModelContinuation(
            source: "openai.responses.v1", model: "gpt-6.1-sol",
            state: try JSONSerialization.data(withJSONObject: [
                reasoning, VyronResponsesTestSupport.textOutput("Inspecting"),
                VyronResponsesTestSupport.toolOutput("old-call")
            ])
        ))
        let client = try VyronResponsesTestSupport.client(settings: ModelSettings(contextTokens: 16_384))
        let step = try await client.developmentStep(model: "gpt-6.1-sol", messages: [
            DevelopmentMessage(role: "system", content: "Keep the user's requirements"), old,
            DevelopmentMessage(role: "tool", content: "old files", toolName: "list_files", toolCallID: "old-call"),
            DevelopmentMessage(role: "assistant", content: "Completed summary."),
            DevelopmentMessage(role: "user", content: "Continue after the summary")
        ], mode: .plan)
        XCTAssertEqual(step.message.content, "Continuing.")
    }
}
