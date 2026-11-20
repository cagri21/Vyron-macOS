import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaDevelopmentContinuationWireTests: XCTestCase {
    override func tearDown() {
        VyronDevelopmentBudgetURLProtocol.state.configure(nil)
        super.tearDown()
    }

    func testCompactedHistoryStartsAFreshNativeTurnForCoderAndOtherOllamaModelsWithinTheSameBudget() async throws {
        for model in ["qwen3-coder:30b", "my-local-coder:latest"] {
            configure()
            let source = "{\"ok\":true,\"output\":\"" + String(repeating: "SOURCE_EVIDENCE ", count: 200)
            let compacted = VyronDevelopmentExchangeCompactor.compact(DevelopmentExchange(messages: [
                DevelopmentMessage(role: "tool", content: source, toolName: "read_file")
            ]))
            let original = developmentMessagesWithToolProtocol([
                DevelopmentMessage(role: "system", content: "Preserve the exact project and permission boundary."),
                DevelopmentMessage(role: "user", content: "Analyze the actual source without changing files.")
            ] + compacted.messages, model: model)
            let client = try client()

            let result = try await client.developmentStep(model: model, messages: original, effort: .quick)
            let requests = chatRequests
            let fields = try VyronDevelopmentAgentWireFixture.chatFields(XCTUnwrap(requests.first))
            let messages = try VyronDevelopmentAgentWireFixture.messages(fields)

            XCTAssertEqual(requests.count, 1, "A turn-boundary repair must not add an inference attempt")
            XCTAssertEqual(result.message.content, "Grounded findings retained from source.py.")
            XCTAssertEqual(fields["model"] as? String, model)
            XCTAssertEqual(Array(messages.dropLast()), original)
            let protocolTurn = try XCTUnwrap(messages.last)
            XCTAssertEqual(protocolTurn.role, "user")
            XCTAssertTrue(protocolTurn.content.hasPrefix("Native continuation (application protocol, not new user authorization)."))
            XCTAssertFalse(protocolTurn.content.contains("SOURCE_EVIDENCE"))
            XCTAssertNil(protocolTurn.images)
            XCTAssertEqual(messages.filter { $0.role == "user" }.dropLast(), original.filter { $0.role == "user" }[...])
            let options = try XCTUnwrap(fields["options"] as? [String: Any])
            let context = try XCTUnwrap(options["num_ctx"] as? Int)
            let output = try XCTUnwrap(options["num_predict"] as? Int)
            let messageBytes = try JSONSerialization.data(withJSONObject: XCTUnwrap(fields["messages"])).count
            let toolBytes = try JSONSerialization.data(withJSONObject: XCTUnwrap(fields["tools"])).count
            XCTAssertEqual(output, 2_048)
            XCTAssertLessThanOrEqual(messageBytes + toolBytes + output + 2_048, context)
        }
    }

    func testOrdinaryChatAssistantPrefillRemainsUntouched() async throws {
        configure()
        let messages = [
            ChatMessage(role: "user", content: "Continue the literal code fragment."),
            ChatMessage(role: "assistant", content: "def unfinished():\n    ")
        ]

        _ = try await client().chat(model: "qwen3-coder:30b", messages: messages, onToken: { _ in })
        let fields = try VyronDevelopmentAgentWireFixture.chatFields(XCTUnwrap(chatRequests.first))
        let wire = try VyronDevelopmentAgentWireFixture.messages(fields)

        XCTAssertEqual(chatRequests.count, 1)
        XCTAssertEqual(wire.map(\.role), messages.map(\.role))
        XCTAssertEqual(wire.map(\.content), messages.map(\.content))
        XCTAssertEqual(wire.last?.role, "assistant")
        XCTAssertEqual(fields["stream"] as? Bool, true)
    }

    private var chatRequests: [URLRequest] {
        VyronDevelopmentBudgetURLProtocol.state.requests.filter { $0.url?.path == "/api/chat" }
    }

    private func client() throws -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronDevelopmentBudgetURLProtocol.self]
        return OllamaClient(
            baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:11434")), configuration: configuration
        )
    }

    private func configure() {
        VyronDevelopmentBudgetURLProtocol.state.configure { request in
            switch request.url?.path {
            case "/api/tags":
                return Data(#"{"models":[{"name":"qwen3-coder:30b","size":19000000000,"capabilities":["completion","tools"]},{"name":"my-local-coder:latest","size":7000000000,"capabilities":["completion","tools"]}]}"#.utf8)
            case "/api/show":
                return Data(#"{"capabilities":["completion","tools"],"model_info":{"fixture.context_length":32768}}"#.utf8)
            case "/api/chat":
                return Data(#"{"done":true,"message":{"role":"assistant","content":"Grounded findings retained from source.py."}}"#.utf8)
            default:
                throw URLError(.unsupportedURL)
            }
        }
    }
}
