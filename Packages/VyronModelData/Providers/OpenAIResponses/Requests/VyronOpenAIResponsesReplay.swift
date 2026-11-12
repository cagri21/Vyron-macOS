import Foundation
import VyronLocalization
import VyronModelDomain

enum VyronOpenAIResponsesReplay {
    static func scopedMessages(_ messages: [DevelopmentMessage], model: String) -> [DevelopmentMessage] {
        messages.map { message in
            guard message.role == "assistant", let continuation = message.continuation,
                continuation.source != VyronOpenAIResponsesLimits.continuationSource || continuation.model != model
            else {
                return message
            }
            return message.discardingContinuation()
        }
    }

    static func input(_ messages: [DevelopmentMessage], model: String) throws -> [DevelopmentJSONValue] {
        try VyronDevelopmentImageContext.validate(messages)
        var input: [DevelopmentJSONValue] = []
        var pending: Set<String> = []
        var seen: Set<String> = []
        for message in messages {
            switch message.role {
            case "system", "user":
                guard pending.isEmpty, message.toolCalls?.isEmpty != false, message.continuation == nil else {
                    throw invalidReplay
                }
                input += try VyronOpenAIResponsesWire.chatInput(
                    [
                        ChatMessage(role: message.role, content: message.content, images: message.images ?? [])
                    ],
                    systemPrompt: nil
                )
            case "assistant":
                guard pending.isEmpty else { throw invalidReplay }
                let calls = message.toolCalls ?? []
                guard calls.count <= VyronOpenAIResponsesLimits.maximumCalls else { throw invalidReplay }
                for call in calls {
                    guard let id = call.id, VyronOpenAIResponsesOutput.validIdentifier(id), seen.insert(id).inserted
                    else {
                        throw invalidReplay
                    }
                    pending.insert(id)
                }
                if let replay = try continuedItems(message, model: model) {
                    input += replay
                } else {
                    if !message.content.isEmpty {
                        input.append(VyronOpenAIResponsesWire.message(role: "assistant", content: message.content))
                    }
                    input += try calls.map(functionItem)
                }
            case "tool":
                guard let id = message.toolCallID, pending.remove(id) != nil,
                    message.toolCalls?.isEmpty != false, message.continuation == nil
                else { throw invalidReplay }
                input.append(
                    .object([
                        "type": .string("function_call_output"), "call_id": .string(id),
                        "output": .string(message.content)
                    ])
                )
            default:
                throw invalidReplay
            }
        }
        guard pending.isEmpty else { throw invalidReplay }
        return input
    }

    private static var invalidReplay: ModelProviderError {
        .invalidResponse(VyronModelDataText.invalidNativeToolExchange)
    }

    private static func continuedItems(_ message: DevelopmentMessage, model: String) throws -> [DevelopmentJSONValue]? {
        guard let continuation = message.continuation,
            continuation.source == VyronOpenAIResponsesLimits.continuationSource,
            continuation.model == model
        else { return nil }
        guard continuation.state.count <= VyronOpenAIResponsesLimits.responseBytes else { throw invalidReplay }
        let items = try JSONDecoder().decode([DevelopmentJSONValue].self, from: continuation.state)
        let replay = try VyronOpenAIResponsesOutput(items: items)
        guard replay.message.role == message.role, replay.message.content == message.content,
            (replay.message.toolCalls ?? []) == (message.toolCalls ?? []), message.toolName == nil,
            message.toolCallID == nil
        else { throw invalidReplay }
        return items
    }

    private static func functionItem(_ call: DevelopmentToolCall) throws -> DevelopmentJSONValue {
        guard let id = call.id, VyronOpenAIResponsesOutput.validIdentifier(id),
            call.function.name.range(
                of: VyronOpenAIResponsesLimits.functionNamePattern,
                options: .regularExpression
            ) != nil
        else {
            throw invalidReplay
        }
        let arguments = try JSONEncoder().encode(call.function.arguments)
        guard arguments.count <= VyronOpenAIResponsesLimits.argumentBytes else { throw invalidReplay }
        return .object([
            "type": .string("function_call"), "call_id": .string(id), "name": .string(call.function.name),
            "arguments": .string(String(decoding: arguments, as: UTF8.self))
        ])
    }
}
