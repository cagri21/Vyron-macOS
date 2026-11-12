import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronOllamaThinkingWireTests: XCTestCase {
    func testAllStructuredRequestShapesEncodeThinkingAsScalarValuesOrOmitAutomatic() throws {
        try assertRequests(nil, expected: nil)
        try assertRequests(.toggle(.enabled), expected: .bool(true))
        try assertRequests(.toggle(.disabled), expected: .bool(false))
        for level in VyronModelThinkingLevel.allCases {
            try assertRequests(.level(level), expected: .string(level.rawValue))
        }
    }

    func testStructuredAndDevelopmentDecodersConsumeOnlyFinalContent() throws {
        let content = #"{"mode":"conversation","goal":null,"clarification":null,"effort":"quick"}"#
        let data = try JSONSerialization.data(withJSONObject: [
            "message": ["role": "assistant", "content": content, "thinking": "NATIVE_REASONING_MARKER"],
            "done": true
        ])
        let structured = try JSONDecoder().decode(ControlPlanningResponse.self, from: data)
        let development = try JSONDecoder().decode(DevelopmentStepResponse.self, from: data)
        XCTAssertEqual(structured.message?.content, content)
        XCTAssertEqual(development.message?.content, content)
        let route = try JSONDecoder().decode(AssistantRoute.self, from: Data(content.utf8))
        XCTAssertEqual(route.mode, .conversation)
        let persisted = try JSONEncoder().encode(development.message)
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("NATIVE_REASONING_MARKER"))
    }

    func testStructuredReasoningHeadroomStaysInsideContextAndExplicitOutputCaps() throws {
        let route = VyronOllamaStructuredOutputBudget(outputTokens: 384, contextTokens: 16_384, inputBytes: 4_000)
        XCTAssertEqual(try route.resolved(reasoningMayRun: true, maximumOutputTokens: nil), 4_096)
        XCTAssertEqual(try route.resolved(reasoningMayRun: false, maximumOutputTokens: nil), 384)
        XCTAssertEqual(try route.resolved(reasoningMayRun: true, maximumOutputTokens: 1_024), 1_024)
        let nearLimit = VyronOllamaStructuredOutputBudget(outputTokens: 512, contextTokens: 8_192, inputBytes: 5_000)
        XCTAssertEqual(try nearLimit.resolved(reasoningMayRun: true, maximumOutputTokens: nil), 1_144)
        let oversized = VyronOllamaStructuredOutputBudget(outputTokens: 512, contextTokens: 8_192, inputBytes: 8_000)
        XCTAssertThrowsError(try oversized.resolved(reasoningMayRun: true, maximumOutputTokens: nil))
    }

    private func assertRequests(
        _ thinking: VyronOllamaThinkingValue?,
        expected: DevelopmentJSONValue?
    ) throws {
        let control = ControlPlanningRequest(model: "fixture", messages: [], think: thinking)
        let intent = IntentRoutingRequest(
            model: "fixture", messages: [], think: thinking, options: .init(num_ctx: 8_192)
        )
        let agent = AgentPlanningRequest(
            model: "fixture", messages: [], options: .init(num_ctx: 8_192, num_predict: 1_024), think: thinking
        )
        let development = DevelopmentStepRequest(
            model: "fixture", messages: [], think: thinking, tools: [],
            options: .init(num_ctx: 8_192, num_predict: 1_024)
        )
        for request in [try fields(control), try fields(intent), try fields(agent), try fields(development)] {
            XCTAssertEqual(request["think"], expected)
            XCTAssertEqual(request["stream"], .bool(false))
        }
    }

    private func fields<Value: Encodable>(_ value: Value) throws -> [String: DevelopmentJSONValue] {
        try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: JSONEncoder().encode(value))
    }
}
