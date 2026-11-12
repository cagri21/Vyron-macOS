import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronDeepSeekReplayTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testReasoningCannotCrossHostConnectionOrModelBoundaries() async throws {
        let original = VyronDeepSeekTestSupport.profile()
        let scope = try XCTUnwrap(VyronDeepSeekReplayScope(
            connection: original, model: VyronDeepSeekTestSupport.model
        ))
        let assistant = try scope.retaining(
            DevelopmentMessage(role: "assistant", content: "Prior visible answer"),
            reasoning: "private-original-reasoning"
        )
        var otherHost = original
        otherHost.endpoint = "https://api.deepseek.com.example.test/v1"
        var otherConnection = original
        otherConnection.id = UUID()
        var otherModel = original
        otherModel.selectedModel = "deepseek-v4-pro"
        for target in [otherHost, otherConnection, otherModel] {
            let official = VyronDeepSeekRoute.matches(target)
            let model = target.selectedModel
            await VyronResponsesTestURLProtocol.state.reset { request, _ in
                if request.url?.path == "/v1/models" { return try VyronDeepSeekTestSupport.models(model) }
                let body = try VyronResponsesTestSupport.body(request)
                let wire = try VyronResponsesTestSupport.json(body)
                XCTAssertFalse(wire.contains("private-original-reasoning"))
                XCTAssertFalse(wire.contains("continuation"))
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                let prior = messages.first { $0["role"] as? String == "assistant" }
                XCTAssertEqual(prior?["content"] as? String, "Prior visible answer")
                if official {
                    XCTAssertEqual(prior?["reasoning_content"] as? String, "")
                } else {
                    XCTAssertNil(prior?["reasoning_content"])
                    XCTAssertNil(body["thinking"])
                    XCTAssertNil(body["reasoning_effort"])
                }
                return try VyronDeepSeekTestSupport.completion(content: "New answer")
            }
            let reply = try await VyronDeepSeekTestSupport.client(target).developmentStep(
                model: model, messages: [assistant, DevelopmentMessage(role: "user", content: "Continue")],
                mode: .plan
            )
            XCTAssertEqual(reply.message.content, "New answer")
            if !official { XCTAssertNil(reply.message.continuation) }
        }
    }

    func testTamperedOpaqueStateAndNonAssistantMetadataCannotBeReplayed() throws {
        let scope = try XCTUnwrap(VyronDeepSeekReplayScope(
            connection: VyronDeepSeekTestSupport.profile(), model: VyronDeepSeekTestSupport.model
        ))
        let first = try scope.retaining(
            DevelopmentMessage(role: "assistant", content: "Original"), reasoning: "private-state"
        )
        let state = try XCTUnwrap(first.continuation)
        let tampered = DevelopmentMessage(
            message: DevelopmentMessage(role: "assistant", content: "Changed"), continuation: state
        )
        XCTAssertThrowsError(try scope.reasoning(for: tampered))
        let toolChanged = DevelopmentMessage(message: DevelopmentMessage(
            role: "assistant", content: "Original",
            toolCalls: [DevelopmentToolCall(name: "write_file", arguments: [:], id: "injected")]
        ), continuation: state)
        XCTAssertThrowsError(try scope.reasoning(for: toolChanged))
        let user = DevelopmentMessage(
            message: DevelopmentMessage(role: "user", content: "Original"), continuation: state
        )
        XCTAssertNil(scope.scoped([user]).first?.continuation)
        XCTAssertNil(try scope.reasoning(for: user))
    }

    func testCompactedExchangeDropsOpaqueReasoningAndUsesEmptyAssistantField() throws {
        let scope = try XCTUnwrap(VyronDeepSeekReplayScope(
            connection: VyronDeepSeekTestSupport.profile(), model: VyronDeepSeekTestSupport.model
        ))
        let assistant = try scope.retaining(DevelopmentMessage(
            role: "assistant", content: "Reading", toolCalls: [DevelopmentToolCall(
                name: "list_files", arguments: [:], id: "call-compact"
            )]
        ), reasoning: "private-compact-reasoning")
        let compacted = VyronDevelopmentRequestBudget.compactingCompletedExchanges(in: [
            assistant, DevelopmentMessage(
                role: "tool", content: "README.md", toolName: "list_files", toolCallID: "call-compact"
            )
        ])
        XCTAssertTrue(compacted.allSatisfy { $0.continuation == nil })
        let wire = try compacted.map { try VyronCompatibleMessage($0, scope: scope) }
        let text = String(decoding: try JSONEncoder().encode(wire), as: UTF8.self)
        XCTAssertFalse(text.contains("private-compact-reasoning"))
        for message in wire where message.role == "assistant" {
            XCTAssertEqual(message.reasoningContent, "")
        }
    }

    func testDeepSeekSettingsAreSelectionSpecificAndPersistWithoutSchemaMigration() throws {
        for enabled in [true, false] {
            let profile = VyronDeepSeekTestSupport.profile(settings: ModelSettings(thinking: enabled))
            let validated = try profile.validated()
            let restored = try JSONDecoder().decode(
                ModelConnectionProfile.self, from: JSONEncoder().encode(validated)
            )
            XCTAssertEqual(restored.id, profile.id)
            XCTAssertEqual(restored.settings.thinking, enabled)
        }
        var thirdParty = VyronDeepSeekTestSupport.profile(settings: ModelSettings(thinking: true))
        thirdParty.endpoint = "https://models.example.test/v1"
        XCTAssertThrowsError(try thirdParty.validated())
        var unknown = VyronDeepSeekTestSupport.profile(settings: ModelSettings(thinking: true))
        unknown.selectedModel = "future-model"
        XCTAssertThrowsError(try unknown.validated())
        var named = VyronDeepSeekTestSupport.profile()
        named.settings.thinkingLevel = .high
        XCTAssertThrowsError(try named.validated())
    }

    func testEffortMappingUsesOnlyDeepSeekPublishedValues() {
        let expected: [AgentEffort: String] = [
            .automatic: "high", .quick: "low", .balanced: "high", .deep: "high",
            .extraHigh: "high", .maximum: "max", .ultra: "max"
        ]
        for effort in AgentEffort.allCases {
            let configuration = VyronDeepSeekRequestConfiguration(settings: ModelSettings(), effort: effort)
            XCTAssertTrue(configuration.enabled)
            XCTAssertEqual(configuration.effort, expected[effort])
        }
    }
}
