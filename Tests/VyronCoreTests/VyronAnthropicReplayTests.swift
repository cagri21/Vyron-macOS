import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronAnthropicReplayTests: XCTestCase {
    func testSignedThinkingReplaysOnlyWithTheOriginalModelAndInputPrefix() throws {
        let model = "claude-sonnet-4-6"
        let user = DevelopmentMessage(role: "user", content: "List the project's files.")
        let system = DevelopmentMessage(role: "system", content: "Use the workspace tools.")
        let tools = try DevelopmentToolDefinition.available(mode: .plan, externalTools: []).map(VyronAnthropicWire.tool)
        let prefix = try VyronAnthropicWire.developmentInput([system, user], model: model, tools: tools)
        let digest = try VyronAnthropicWire.prefixDigest(prefix, tools: tools)
        let originalContent: [DevelopmentJSONValue] = [
            .object(["type": .string("thinking"), "thinking": .string("Private draft."),
                     "signature": .string("Zml4dHVyZQ==")]),
            .object(["type": .string("text"), "text": .string("I'll list the files.")]),
            .object(["type": .string("tool_use"), "id": .string("toolu_list_files"), "name": .string("list_files"),
                     "input": .object([:])])
        ]
        let assistant = try VyronAnthropicWire.developmentMessage(
            content: originalContent, stopReason: "tool_use", model: model, prefixDigest: digest
        )
        XCTAssertEqual(assistant.content, "I'll list the files.")
        XCTAssertNotNil(assistant.continuation)
        let result = DevelopmentMessage(
            role: "tool", content: "README.md", toolName: "list_files", toolCallID: "toolu_list_files"
        )

        let history = [system, user, assistant, result]
        let original = try VyronAnthropicWire.developmentInput(history, model: model, tools: tools)
        XCTAssertEqual(try assistantContent(original), originalContent)

        let editedSystem = DevelopmentMessage(role: "system", content: "Use only read-only workspace tools.")
        let edited = try VyronAnthropicWire.developmentInput([editedSystem, user, assistant, result],
            model: model, tools: tools)
        let switchedModel = try VyronAnthropicWire.developmentInput(history, model: "claude-opus-4-7", tools: tools)
        let changedTools = try VyronAnthropicWire.developmentInput(history, model: model, tools: Array(tools.dropLast()))
        for replay in [edited, switchedModel, changedTools] {
            XCTAssertEqual(try assistantContent(replay), Array(originalContent.dropFirst()))
            XCTAssertEqual(replay.messages.last, original.messages.last)
        }
    }

    private func assistantContent(_ input: VyronAnthropicInput) throws -> [DevelopmentJSONValue] {
        let content = input.messages.compactMap { message -> [DevelopmentJSONValue]? in
            guard case .object(let fields) = message, fields["role"] == .string("assistant"),
                case .array(let content) = fields["content"] else { return nil }
            return content
        }
        return try XCTUnwrap(content.first)
    }
}
