import CryptoKit
import Foundation
import VyronLocalization
import VyronModelDomain

enum VyronAnthropicWire {
    static let maximumResponseBytes = 2_097_152
    static let maximumArgumentBytes = 64_000
    static let maximumToolCalls = 4
    private static let maximumRequestBytes = 25_165_824
    private static let continuationSource = "anthropic.messages.v1"
    private static let toolNamePattern = "^[a-zA-Z0-9_-]{1,64}$"

    static func chatInput(
        _ messages: [ChatMessage],
        systemPrompt: String?,
        retainingEmptyUserTurns: Bool = false
    ) throws -> VyronAnthropicInput {
        try VyronImageAttachment.validate(messages: messages)
        var input = VyronAnthropicInput()
        if let systemPrompt, !systemPrompt.isEmpty {
            input.system.append(textBlock(systemPrompt))
        }
        for message in messages {
            switch message.role {
            case "system":
                if !message.content.isEmpty { input.system.append(textBlock(message.content)) }
            case "user", "assistant":
                let blocks = contentBlocks(text: message.content, images: message.images)
                if !blocks.isEmpty || (retainingEmptyUserTurns && message.role == "user") {
                    input.messages.append(turn(role: message.role, content: blocks))
                }
            default:
                throw ModelProviderError.invalidResponse(VyronModelDataText.claudeUnsupportedRole)
            }
        }
        return input
    }

    static func developmentInput(
        _ messages: [DevelopmentMessage],
        model: String? = nil,
        tools: [DevelopmentJSONValue] = [],
        retainingEmptyUserTurns: Bool = false
    ) throws -> VyronAnthropicInput {
        try VyronDevelopmentImageContext.validate(messages)
        var input = VyronAnthropicInput()
        input.system = messages.filter { $0.role == "system" && !$0.content.isEmpty }.map { textBlock($0.content) }
        var pending: Set<String> = []
        var seen: Set<String> = []
        var toolResults: [DevelopmentJSONValue] = []
        for message in messages {
            switch message.role {
            case "system":
                guard pending.isEmpty, message.images?.isEmpty != false, message.toolCalls?.isEmpty != false else {
                    throw invalidReplay
                }
            case "user":
                guard pending.isEmpty, message.toolCalls?.isEmpty != false else { throw invalidReplay }
                let blocks = contentBlocks(text: message.content, images: message.images)
                if !blocks.isEmpty || retainingEmptyUserTurns {
                    input.messages.append(turn(role: "user", content: blocks))
                }
            case "assistant":
                guard pending.isEmpty, message.images?.isEmpty != false else { throw invalidReplay }
                let calls = message.toolCalls ?? []
                guard calls.count <= maximumToolCalls else { throw invalidReplay }
                for call in calls {
                    guard let id = call.id, validIdentifier(id), seen.insert(id).inserted else { throw invalidReplay }
                    pending.insert(id)
                }
                let blocks = try replayBlocks(message, model: model, input: input, tools: tools)
                if !blocks.isEmpty { input.messages.append(turn(role: "assistant", content: blocks)) }
            case "tool":
                guard let id = message.toolCallID, pending.remove(id) != nil,
                    message.toolCalls?.isEmpty != false, message.images?.isEmpty != false
                else { throw invalidReplay }
                toolResults.append(
                    .object([
                        "type": .string("tool_result"), "tool_use_id": .string(id), "content": .string(message.content)
                    ])
                )
                if pending.isEmpty {
                    input.messages.append(turn(role: "user", content: toolResults))
                    toolResults.removeAll(keepingCapacity: true)
                }
            default:
                throw invalidReplay
            }
        }
        guard pending.isEmpty else { throw invalidReplay }
        return input
    }

    static func tool(_ definition: DevelopmentToolDefinition) throws -> DevelopmentJSONValue {
        let parameters = try JSONDecoder().decode(
            DevelopmentJSONValue.self,
            from: JSONEncoder().encode(definition.function.parameters)
        )
        return .object([
            "name": .string(definition.function.name),
            "description": .string(definition.function.description),
            "input_schema": parameters
        ])
    }

    static func request(
        model: String,
        input: VyronAnthropicInput,
        options: VyronAnthropicRequestOptions
    ) throws -> Data {
        guard !input.messages.isEmpty else {
            throw ModelProviderError.invalidSettings(VyronModelDataText.claudeMessagesRequired)
        }
        var body: [String: DevelopmentJSONValue] = ["model": .string(model), "messages": .array(input.messages)]
        if !input.system.isEmpty { body["system"] = .array(input.system) }
        if !options.tools.isEmpty { body["tools"] = .array(options.tools) }
        if let maximumOutputTokens = options.maximumOutputTokens {
            body["max_tokens"] = .number(Double(maximumOutputTokens))
            if options.stream { body["stream"] = .bool(true) }
        }
        let data = try JSONEncoder().encode(body)
        guard data.count <= maximumRequestBytes else { throw DevelopmentAgentError.contextBudget }
        return data
    }

    /// Signed thinking is usable only while Claude's system, messages, and tools prefix remains intact.
    static func prefixDigest(_ input: VyronAnthropicInput, tools: [DevelopmentJSONValue]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let prefix = try encoder.encode([
            "system": input.system,
            "messages": input.messages,
            "tools": tools
        ])
        return Data(SHA256.hash(data: prefix))
    }

    static func developmentMessage(
        _ data: Data,
        model: String? = nil,
        prefixDigest: Data? = nil
    ) throws -> DevelopmentMessage {
        guard data.count <= maximumResponseBytes else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.claudeResponseTooLarge)
        }
        let document = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: data)
        guard document["role"] == .string("assistant"), case .array(let content) = document["content"],
            case .string(let stopReason) = document["stop_reason"]
        else { throw invalidResponse }
        return try developmentMessage(
            content: content,
            stopReason: stopReason,
            model: model,
            prefixDigest: prefixDigest
        )
    }

    static func developmentMessage(
        content: [DevelopmentJSONValue],
        stopReason: String,
        model: String?,
        prefixDigest: Data?
    ) throws -> DevelopmentMessage {
        switch stopReason {
        case "end_turn", "tool_use", "stop_sequence": break
        case "max_tokens": throw ModelProviderError.outputLimitReached
        case "model_context_window_exceeded": throw DevelopmentAgentError.contextBudget
        case "refusal": throw ModelProviderError.invalidResponse(VyronModelDataText.claudeDeclinedRequest)
        default: throw invalidResponse
        }
        let message = try outputMessage(content)
        let hasCalls = message.toolCalls?.isEmpty == false
        guard (stopReason == "tool_use") == hasCalls else { throw invalidResponse }
        guard hasCalls, let model, let prefixDigest, content.contains(where: isThinking) else { return message }
        let state = try JSONEncoder().encode(VyronAnthropicContinuation(prefixDigest: prefixDigest, content: content))
        guard state.count <= maximumResponseBytes else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.claudeContinuationTooLarge)
        }
        let continuation = VyronModelContinuation(
            source: continuationSource,
            model: model,
            state: state
        )
        return DevelopmentMessage(message: message, continuation: continuation)
    }

    private static var invalidReplay: ModelProviderError {
        .invalidResponse(VyronModelDataText.claudeInvalidToolExchange)
    }

    private static var invalidResponse: ModelProviderError {
        .invalidResponse(VyronModelDataText.claudeIncompleteResponse)
    }

    private static func textBlock(_ text: String) -> DevelopmentJSONValue {
        .object(["type": .string("text"), "text": .string(text)])
    }

    private static func turn(role: String, content: [DevelopmentJSONValue]) -> DevelopmentJSONValue {
        .object(["role": .string(role), "content": .array(content)])
    }

    private static func contentBlocks(text: String, images: [VyronImageAttachment]?) -> [DevelopmentJSONValue] {
        let textBlocks = text.isEmpty ? [] : [textBlock(text)]
        let imageBlocks: [DevelopmentJSONValue] = (images ?? []).map { image in
            .object([
                "type": .string("image"),
                "source": .object([
                    "type": .string("base64"), "media_type": .string(image.mimeType),
                    "data": .string(image.data.base64EncodedString())
                ])
            ])
        }
        return textBlocks + imageBlocks
    }

    private static func replayBlocks(
        _ message: DevelopmentMessage,
        model: String?,
        input: VyronAnthropicInput,
        tools: [DevelopmentJSONValue]
    ) throws -> [DevelopmentJSONValue] {
        if let continuation = message.continuation, continuation.source == continuationSource,
            continuation.model == model {
            guard continuation.state.count <= maximumResponseBytes else { throw invalidReplay }
            let state = try JSONDecoder().decode(VyronAnthropicContinuation.self, from: continuation.state)
            if state.prefixDigest == (try prefixDigest(input, tools: tools)) {
                let replay = try outputMessage(state.content)
                guard replay.content == message.content, replay.toolCalls == message.toolCalls else {
                    throw invalidReplay
                }
                return state.content
            }
        }
        return try contentBlocks(text: message.content, images: nil) + (message.toolCalls ?? []).map(toolUseBlock)
    }

    private static func toolUseBlock(_ call: DevelopmentToolCall) throws -> DevelopmentJSONValue {
        guard let id = call.id, validIdentifier(id), validToolName(call.function.name),
            try JSONEncoder().encode(call.function.arguments).count <= maximumArgumentBytes
        else { throw invalidReplay }
        return .object([
            "type": .string("tool_use"), "id": .string(id), "name": .string(call.function.name),
            "input": .object(call.function.arguments)
        ])
    }

    private static func outputMessage(_ content: [DevelopmentJSONValue]) throws -> DevelopmentMessage {
        var text = ""
        var calls: [DevelopmentToolCall] = []
        var identifiers: Set<String> = []
        for item in content {
            guard case .object(let block) = item else { throw invalidResponse }
            switch block["type"] {
            case .string("text"):
                guard case .string(let value) = block["text"] else { throw invalidResponse }
                text += value
            case .string("tool_use"):
                let call = try toolCall(block)
                guard let id = call.id, identifiers.insert(id).inserted, calls.count < maximumToolCalls else {
                    throw DevelopmentAgentError.invalidTool(VyronModelDataText.claudeInvalidToolIDs)
                }
                calls.append(call)
            case .string("thinking"):
                guard case .string = block["thinking"], case .string(let signature) = block["signature"],
                    !signature.isEmpty
                else { throw invalidResponse }
            case .string("redacted_thinking"):
                guard case .string(let data) = block["data"], !data.isEmpty else { throw invalidResponse }
            default:
                throw ModelProviderError.invalidResponse(VyronModelDataText.claudeUnsupportedContent)
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.claudeNoAnswerOrTool)
        }
        return DevelopmentMessage(role: "assistant", content: text, toolCalls: calls.isEmpty ? nil : calls)
    }

    private static func toolCall(_ block: [String: DevelopmentJSONValue]) throws -> DevelopmentToolCall {
        guard case .string(let id) = block["id"], validIdentifier(id),
            case .string(let name) = block["name"], validToolName(name),
            case .object(let arguments) = block["input"],
            try JSONEncoder().encode(arguments).count <= maximumArgumentBytes
        else {
            throw DevelopmentAgentError.invalidTool(VyronModelDataText.claudeInvalidToolCall)
        }
        return DevelopmentToolCall(name: name, arguments: arguments, id: id)
    }

    private static func isThinking(_ item: DevelopmentJSONValue) -> Bool {
        guard case .object(let block) = item else { return false }
        return block["type"] == .string("thinking") || block["type"] == .string("redacted_thinking")
    }

    private static func validToolName(_ name: String) -> Bool {
        name.range(of: toolNamePattern, options: .regularExpression) != nil
    }

    private static func validIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 512
            && !id.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
            })
    }
}
