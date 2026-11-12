import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronDevelopmentRequestBudgetTests: XCTestCase, @unchecked Sendable {
    override func tearDown() {
        VyronDevelopmentBudgetURLProtocol.state.configure(nil)
        super.tearDown()
    }

    func testQwenProtocolOverheadCompactsOlderCompleteExchange() throws {
        let messages = try sizedMessages(byteCount: 23_900)
        let adapted = developmentMessagesWithToolProtocol(messages, model: "qwen3-coder:30b")
        XCTAssertEqual(try JSONEncoder().encode(messages).count, 23_900)
        XCTAssertGreaterThan(try JSONEncoder().encode(adapted).count, 24_000)

        let tools = try DevelopmentToolDefinition.available(mode: .agent, externalTools: [])
        let bounded = try VyronDevelopmentRequestBudget.messages(
            adapted, tools: tools, budget: .init(contextTokens: 32_768)
        )

        XCTAssertLessThanOrEqual(try JSONEncoder().encode(bounded).count, 24_000)
        XCTAssertEqual(bounded.filter { ["user", "system"].contains($0.role) },
                       adapted.filter { ["user", "system"].contains($0.role) })
        XCTAssertFalse(bounded.contains { $0.content.hasPrefix("old exchange") })
        XCTAssertEqual(Array(bounded.suffix(3)), Array(adapted.suffix(3)))
        XCTAssertEqual(try VyronDevelopmentRequestBudget.messages(
            bounded, tools: tools, budget: .init(contextTokens: 32_768)
        ), bounded)
    }

    func testToolSchemasAndContextAreIncludedBeforeCompaction() throws {
        let messages = try sizedMessages(byteCount: 18_000)
        let external = DevelopmentExternalTool(
            name: "project_reference",
            description: String(repeating: "Reference detail. ", count: 150),
            inputSchema: ["type": .string("object"), "properties": .object([:])],
            isReadOnly: true
        )
        let tools = try DevelopmentToolDefinition.available(mode: .agent, externalTools: [external])
        let bounded = try VyronDevelopmentRequestBudget.messages(
            messages, tools: tools, budget: .init(contextTokens: 16_384)
        )
        let input = try JSONEncoder().encode(bounded).count + JSONEncoder().encode(tools).count + 2_048

        XCTAssertLessThanOrEqual(input + 512, 16_384)
        XCTAssertFalse(bounded.contains { $0.content.hasPrefix("old exchange") })
        XCTAssertEqual(bounded.filter { $0.role == "user" }, messages.filter { $0.role == "user" })
        XCTAssertEqual(Array(bounded.suffix(3)), Array(messages.suffix(3)))
    }

    func testActualWireEncodingControlsCompactionAndRawLimitRemainsBounded() throws {
        let messages = try sizedMessages(byteCount: 20_000)
        let bounded = try VyronDevelopmentRequestBudget.messages(
            messages,
            tools: [],
            budget: .init(contextTokens: 32_768),
            encodedMessageBytes: { try JSONEncoder().encode($0).count + 5_000 }
        )

        XCTAssertLessThanOrEqual(try JSONEncoder().encode(bounded).count + 5_000, 24_000)
        XCTAssertEqual(Array(bounded.suffix(3)), Array(messages.suffix(3)))
    }

    func testIrreducibleUserGuidanceAndLatestExchangeFailWithoutTruncation() throws {
        let messages = try sizedMessages(byteCount: 23_900)
        let latestOnly = Array(messages.prefix(2)) + Array(messages.suffix(3))
        let oversizedUser = DevelopmentMessage(role: "user", content: String(repeating: "u", count: 24_000))
        let oversizedAssistant = DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
            name: "write_file", arguments: ["content": .string(String(repeating: "x", count: 24_000))]
        )])
        let oversizedExchange = Array(messages.prefix(2)) + [
            oversizedAssistant, DevelopmentMessage(role: "tool", content: "Saved", toolName: "write_file")
        ]

        for input in [[oversizedUser] + latestOnly, oversizedExchange] {
            XCTAssertThrowsError(try VyronDevelopmentRequestBudget.messages(
                input, tools: [], budget: .init(contextTokens: 32_768)
            )) { XCTAssertEqual($0 as? DevelopmentAgentError, .contextBudget) }
        }
        XCTAssertThrowsError(try VyronDevelopmentRequestBudget.messages(
            [oversizedUser], tools: [], budget: .init(contextTokens: 32_768)
        )) { XCTAssertEqual($0 as? DevelopmentAgentError, .contextBudget) }
    }

    func testRequestedOutputReservationRemovesOlderExchangeAndKeepsCurrentGuidance() throws {
        let messages = try sizedMessages(byteCount: 13_000)
        let minimumReservation = try VyronDevelopmentRequestBudget.messages(
            messages, tools: [], budget: .init(contextTokens: 16_384)
        )
        XCTAssertEqual(minimumReservation, messages)

        let bounded = try VyronDevelopmentRequestBudget.messages(
            messages, tools: [], budget: .init(contextTokens: 16_384, outputTokens: 4_096)
        )

        XCTAssertFalse(bounded.contains { $0.content.hasPrefix("old exchange") })
        XCTAssertEqual(bounded.filter { ["system", "user"].contains($0.role) },
                       messages.filter { ["system", "user"].contains($0.role) })
        XCTAssertEqual(Array(bounded.suffix(3)), Array(messages.suffix(3)))
        let input = try JSONEncoder().encode(bounded).count + JSONEncoder().encode([DevelopmentToolDefinition]()).count
        XCTAssertLessThanOrEqual(input + 2_048 + 4_096, 16_384)
    }

    func testRequestedOutputReservationRejectsOversizedAuthoritativePromptWithoutTruncation() throws {
        let guidance = [
            DevelopmentMessage(role: "system", content: "Retain every project instruction."),
            DevelopmentMessage(role: "user", content: String(repeating: "u", count: 11_000))
        ]
        XCTAssertEqual(try VyronDevelopmentRequestBudget.messages(
            guidance, tools: [], budget: .init(contextTokens: 16_384)
        ), guidance)

        XCTAssertThrowsError(try VyronDevelopmentRequestBudget.messages(
            guidance, tools: [], budget: .init(contextTokens: 16_384, outputTokens: 4_096)
        )) { XCTAssertEqual($0 as? DevelopmentAgentError, .contextBudget) }
    }

    func testOllamaDispatchesPreviouslyRejectedQwenTranscriptWithinFinalBudget() async throws {
        VyronDevelopmentBudgetURLProtocol.state.configure { request in
            try self.response(for: request, repairsMarkup: false)
        }
        let result = try await client().developmentStep(
            model: "qwen3-coder:30b",
            messages: sizedMessages(byteCount: 23_900)
        )

        XCTAssertEqual(result.message.content, "Finished")
        let requests = chatRequests
        XCTAssertEqual(requests.count, 1)
        let body = try body(of: XCTUnwrap(requests.first))
        let messages = try decodedMessages(in: body)
        XCTAssertFalse(messages.contains { $0.content.hasPrefix("old exchange") })
        XCTAssertTrue(try XCTUnwrap(messages.first).content.contains("required outer <tool_call>"))
        try assertBudget(body)
    }

    func testOllamaRepairReminderIsBudgetedWithoutDroppingUserGuidanceOrLatestPair() async throws {
        let tools = try DevelopmentToolDefinition.available(mode: .agent, externalTools: [])
        let toolBytes = try JSONEncoder().encode(tools).count
        let cap = min(24_000, 32_768 - toolBytes - 2_048 - 512)
        let sample = try sizedMessages(byteCount: 2_000)
        let overhead = try JSONEncoder().encode(
            developmentMessagesWithToolProtocol(sample, model: "qwen3-coder:30b")
        ).count - JSONEncoder().encode(sample).count
        let messages = try sizedMessages(byteCount: cap - overhead - 100)
        VyronDevelopmentBudgetURLProtocol.state.configure { request in
            try self.response(for: request, repairsMarkup: true)
        }

        let result = try await client().developmentStep(model: "qwen3-coder:30b", messages: messages)

        XCTAssertEqual(result.message.content, "Finished")
        let requests = chatRequests
        XCTAssertEqual(requests.count, 2)
        let first = try body(of: XCTUnwrap(requests.first))
        let second = try body(of: XCTUnwrap(requests.last))
        XCTAssertTrue(try decodedMessages(in: first).contains { $0.content.hasPrefix("old exchange") })
        let repaired = try decodedMessages(in: second)
        XCTAssertFalse(repaired.contains { $0.content.hasPrefix("old exchange") })
        XCTAssertEqual(repaired.filter { $0.role == "user" }.dropLast(), messages.filter { $0.role == "user" }[...])
        XCTAssertTrue(try XCTUnwrap(repaired.last).content.contains("No actual tool call was executed"))
        XCTAssertEqual(Array(repaired.dropLast().suffix(3)), Array(messages.suffix(3)))
        try assertBudget(first)
        try assertBudget(second)
    }

    func testCompatibleProviderCompactsBeforeApplyingItsWireContextBudget() async throws {
        VyronDevelopmentBudgetURLProtocol.state.configure { request in
            switch request.url?.path {
            case "/v1/models":
                return Data(#"{"data":[{"id":"budget-model","capabilities":["tools"]}]}"#.utf8)
            case "/v1/chat/completions":
                return Data(#"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"Finished"}}]}"#.utf8)
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronDevelopmentBudgetURLProtocol.self]
        let profile = ModelConnectionProfile(
            name: "Budget fixture",
            kind: .openAICompatible,
            endpoint: "https://budget.example.test",
            settings: ModelSettings(contextTokens: 16_384)
        )
        let provider = try OpenAICompatibleClient(connection: profile, configuration: configuration)

        let result = try await provider.developmentStep(
            model: "budget-model", messages: sizedMessages(byteCount: 18_000)
        )

        XCTAssertEqual(result.message.content, "Finished")
        let request = try XCTUnwrap(VyronDevelopmentBudgetURLProtocol.state.requests.last)
        let body = try body(of: request)
        let wire = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertFalse(wire.contains { ($0["content"] as? String)?.hasPrefix("old exchange") == true })
        XCTAssertEqual(wire.suffix(2).compactMap { $0["tool_call_id"] as? String }, ["first", "second"])
        XCTAssertEqual(wire.filter { $0["role"] as? String == "user" }.compactMap { $0["content"] as? String },
                       ["create a ios template app", "Keep the template minimal."])
        let input = try JSONSerialization.data(withJSONObject: wire).count
            + JSONSerialization.data(withJSONObject: XCTUnwrap(body["tools"])).count + 2_048
        let output = try XCTUnwrap(body["max_tokens"] as? Int)
        XCTAssertGreaterThanOrEqual(output, 512)
        XCTAssertLessThanOrEqual(input + output, 16_384)
    }

    private var chatRequests: [URLRequest] {
        VyronDevelopmentBudgetURLProtocol.state.requests.filter { $0.url?.path == "/api/chat" }
    }

    private func client() throws -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronDevelopmentBudgetURLProtocol.self]
        return OllamaClient(
            baseURL: try XCTUnwrap(URL(string: "http://127.0.0.1:11434")),
            configuration: configuration
        )
    }

    private func response(for request: URLRequest, repairsMarkup: Bool) throws -> Data {
        switch request.url?.path {
        case "/api/tags":
            return Data(#"{"models":[{"name":"qwen3-coder:30b","size":19000000000,"capabilities":["completion","tools"]}]}"#.utf8)
        case "/api/show":
            return Data(#"{"capabilities":["completion","tools"]}"#.utf8)
        case "/api/chat":
            let content = repairsMarkup && chatRequests.count == 1
                ? "<function=read_file>\n<parameter=path>README.md</parameter>\n</function>" : "Finished"
            return try JSONSerialization.data(withJSONObject: [
                "done": true, "message": ["role": "assistant", "content": content]
            ])
        default:
            throw URLError(.unsupportedURL)
        }
    }

    private func sizedMessages(byteCount: Int) throws -> [DevelopmentMessage] {
        func messages(padding: String) -> [DevelopmentMessage] {
            let old = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("README.md")], id: "old")
            let first = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("README.md")], id: "first")
            let second = DevelopmentToolCall(name: "list_files", arguments: [:], id: "second")
            return [
                DevelopmentMessage(role: "system", content: "System rules"),
                DevelopmentMessage(role: "user", content: "create a ios template app"),
                DevelopmentMessage(role: "assistant", content: "old exchange" + padding, toolCalls: [old]),
                DevelopmentMessage(role: "tool", content: "old result", toolName: "read_file", toolCallID: "old"),
                DevelopmentMessage(role: "user", content: "Keep the template minimal."),
                DevelopmentMessage(role: "assistant", toolCalls: [first, second]),
                DevelopmentMessage(role: "tool", content: "current read", toolName: "read_file", toolCallID: "first"),
                DevelopmentMessage(role: "tool", content: "current files", toolName: "list_files", toolCallID: "second")
            ]
        }
        let empty = messages(padding: "")
        let padding = byteCount - (try JSONEncoder().encode(empty).count)
        XCTAssertGreaterThanOrEqual(padding, 0)
        return messages(padding: String(repeating: "x", count: max(0, padding)))
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw try XCTUnwrap(stream.streamError) }
                if count == 0 { break }
                collected.append(contentsOf: buffer.prefix(count))
            }
            data = collected
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decodedMessages(in body: [String: Any]) throws -> [DevelopmentMessage] {
        let data = try JSONSerialization.data(withJSONObject: XCTUnwrap(body["messages"]))
        return try JSONDecoder().decode([DevelopmentMessage].self, from: data)
    }

    private func assertBudget(_ body: [String: Any]) throws {
        let messages = try decodedMessages(in: body)
        let messageBytes = try JSONEncoder().encode(messages).count
        let toolBytes = try JSONSerialization.data(withJSONObject: XCTUnwrap(body["tools"])).count
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        let context = try XCTUnwrap(options["num_ctx"] as? Int)
        let output = try XCTUnwrap(options["num_predict"] as? Int)
        XCTAssertLessThanOrEqual(messageBytes, 24_000)
        XCTAssertGreaterThanOrEqual(output, 512)
        XCTAssertLessThanOrEqual(messageBytes + toolBytes + 2_048 + output, context)
    }
}
