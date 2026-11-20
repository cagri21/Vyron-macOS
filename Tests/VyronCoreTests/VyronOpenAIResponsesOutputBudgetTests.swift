import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOpenAIResponsesOutputBudgetTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testSelectedOpenAIModelsRetainLargeAgentRequestsAndUltraOutput() async throws {
        let models = [
            "gpt-6.1-sol", "gpt-6-sol", "gpt-6-astra", "gpt-6.1-sol-2026-10-07",
            "gpt-6.2-astra", "gpt-6.2-sol", "gpt-6.2-sol-2026-11-18"
        ]
        let guidance = String(repeating: "Follow the project rules.\n", count: 1_500)
        let toolOutput = String(repeating: "Source line from README.md.\n", count: 1_200)
        let messages = [
            DevelopmentMessage(role: "system", content: guidance),
            DevelopmentMessage(role: "user", content: "Inspect the project."),
            DevelopmentMessage(role: "assistant", toolCalls: [
                DevelopmentToolCall(name: "read_file", arguments: ["path": .string("README.md")], id: "read")
            ]),
            DevelopmentMessage(role: "tool", content: toolOutput, toolName: "read_file", toolCallID: "read")
        ]
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            XCTAssertEqual(request.url?.path, "/v1/responses")
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(body["max_output_tokens"] as? Int, 12_288)
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            XCTAssertEqual(input.first?["content"] as? String, guidance)
            XCTAssertEqual(input.last?["call_id"] as? String, "read")
            XCTAssertEqual(input.last?["output"] as? String, toolOutput)
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.textOutput("Project inspected.")
            ]))
        }
        let provider = try VyronResponsesTestSupport.client()

        XCTAssertEqual(provider.developmentMessageBudget(for: "gpt-6-luna").maximumBytes, 24_000)
        for model in models {
            let budget = provider.developmentMessageBudget(for: model)
            XCTAssertEqual(budget.workingBytes, 98_304, model)
            XCTAssertEqual(budget.maximumBytes, 131_072, model)
            let result = try await provider.developmentStep(model: model, messages: messages, effort: .ultra)
            XCTAssertEqual(result.message.content, "Project inspected.", model)
        }
    }

    func testDevelopmentWireRejectsReducedOutputAtAnImageContextBoundary() throws {
        let input: [DevelopmentJSONValue] = [.object([
            "role": .string("user"),
            "content": .array([
                .object(["type": .string("input_text"), "text": .string("Inspect the attached screen.")]),
                .object(["type": .string("input_image"), "image_url": .string("data:image/png;base64,fixture")])
            ])
        ])]
        let estimatedInput: [DevelopmentJSONValue] = [.object([
            "role": .string("user"),
            "content": .array([
                .object(["type": .string("input_text"), "text": .string("Inspect the attached screen.")]),
                .object([
                    "type": .string("input_image"),
                    "image_url": .string(String(repeating: "x", count: VyronImageAttachment.estimatedContextTokens))
                ])
            ])
        ])]
        let tools = try DevelopmentToolDefinition.available(mode: .plan, externalTools: [])
        let toolBytes = try JSONEncoder().encode(tools.map(VyronOpenAIResponsesWire.tool)).count
        let context = try JSONEncoder().encode(estimatedInput).count + toolBytes + 2_048 + 4_096 - 1

        XCTAssertThrowsError(try VyronOpenAIResponsesWire.request(
            model: VyronResponsesTestSupport.model,
            input: input,
            settings: ModelSettings(contextTokens: context, maxOutputTokens: 4_096),
            options: .init(generation: .init(maximumOutputTokens: 4_096, stream: false), tools: tools)
        )) { XCTAssertEqual($0 as? DevelopmentAgentError, .contextBudget) }
    }

    func testDevelopmentReservesSavedOutputAndWireSchemaAtTheContextBoundary() async throws {
        let first = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("README.md")], id: "current")
        let old = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("README.md")], id: "old")
        var messages = [
            DevelopmentMessage(role: "system", content: "Retain project rules."),
            DevelopmentMessage(role: "user", content: "Plan a focused repair."),
            DevelopmentMessage(
                role: "assistant", content: "old exchange", toolCalls: [old]
            ),
            DevelopmentMessage(role: "tool", content: "old result", toolName: "read_file", toolCallID: "old"),
            DevelopmentMessage(role: "user", content: "Preserve existing work."),
            DevelopmentMessage(role: "assistant", toolCalls: [first]),
            DevelopmentMessage(role: "tool", content: "current result", toolName: "read_file", toolCallID: "current")
        ]
        let tools = try DevelopmentToolDefinition.available(mode: .plan, externalTools: [])
        let toolBytes = try JSONEncoder().encode(tools.map(VyronOpenAIResponsesWire.tool)).count
        let inputLimit = 32_768 - toolBytes - 2_048 - 16_384
        let inputBytes = try JSONEncoder().encode(VyronOpenAIResponsesReplay.input(
            messages, model: VyronResponsesTestSupport.model
        )).count
        XCTAssertGreaterThan(inputLimit, inputBytes)
        messages[2] = DevelopmentMessage(
            role: "assistant",
            content: "old exchange" + String(repeating: "x", count: max(0, inputLimit - inputBytes + 1)),
            toolCalls: [old]
        )
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            if request.url?.path == "/v1/models" { return VyronResponsesTestSupport.modelList() }
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(body["max_output_tokens"] as? Int, 16_384)
            let input = try XCTUnwrap(body["input"] as? [[String: Any]])
            XCTAssertFalse(try VyronResponsesTestSupport.json(input).contains("old exchange"))
            XCTAssertEqual(input.filter { $0["role"] as? String == "user" }.compactMap { $0["content"] as? String },
                           ["Plan a focused repair.", "Preserve existing work."])
            XCTAssertEqual(input.filter { $0["type"] as? String == "function_call_output" }
                .compactMap { $0["call_id"] as? String }, ["current"])
            return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
                VyronResponsesTestSupport.textOutput("Plan complete.")
            ]))
        }
        let provider = try VyronResponsesTestSupport.client(settings: ModelSettings(
            contextTokens: 32_768, maxOutputTokens: 16_384
        ))

        let result = try await provider.developmentStep(
            model: VyronResponsesTestSupport.model, messages: messages, effort: .quick, mode: .plan
        )

        XCTAssertEqual(result.message.content, "Plan complete.")
    }
}
