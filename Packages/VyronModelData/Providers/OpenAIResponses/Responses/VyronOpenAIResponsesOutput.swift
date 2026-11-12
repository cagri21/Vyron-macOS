import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronOpenAIResponsesOutput {
    let message: DevelopmentMessage
    let items: [DevelopmentJSONValue]

    init(items: [DevelopmentJSONValue]) throws {
        guard try JSONEncoder().encode(items).count <= VyronOpenAIResponsesLimits.responseBytes else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.oversizedResponse)
        }
        var text = ""
        var hasFinalText = false
        var calls: [DevelopmentToolCall] = []
        for item in items {
            guard case .object(let object) = item else { throw Self.invalidItem }
            if let status = object["status"], status != .string("completed"),
                !(object["type"] == .string("reasoning") && status == .null) {
                throw Self.invalidItem
            }
            switch object["type"] {
            case .string("message"):
                let visible = try Self.messageText(object)
                text += visible
                if object["phase"] != .string("commentary"),
                    !visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hasFinalText = true
                }
            case .string("function_call"):
                calls.append(try Self.functionCall(object))
            case .string("reasoning"):
                try Self.validateReasoning(object)
            default:
                throw ModelProviderError.invalidResponse(VyronModelDataText.unsupportedOutputItem)
            }
        }
        guard calls.count <= VyronOpenAIResponsesLimits.maximumCalls,
            Set(calls.compactMap(\.id)).count == calls.count
        else {
            throw DevelopmentAgentError.invalidTool(VyronModelDataText.invalidOrDuplicateToolCallIDs)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.serverNoAnswerOrTool)
        }
        guard hasFinalText || !calls.isEmpty else {
            throw ModelProviderError.invalidResponse(
                VyronModelDataText.interimCommentaryWithoutAnswer
            )
        }
        self.message = DevelopmentMessage(role: "assistant", content: text, toolCalls: calls.isEmpty ? nil : calls)
        self.items = items
    }

    func continuedMessage(model: String) throws -> DevelopmentMessage {
        let continuation = VyronModelContinuation(
            source: VyronOpenAIResponsesLimits.continuationSource,
            model: model,
            state: try JSONEncoder().encode(items)
        )
        return DevelopmentMessage(message: message, continuation: continuation)
    }

    static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= VyronOpenAIResponsesLimits.identifierBytes
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static var invalidItem: ModelProviderError {
        .invalidResponse(VyronModelDataText.invalidResponseItem)
    }

    private static func messageText(_ object: [String: DevelopmentJSONValue]) throws -> String {
        guard Set(object.keys).isSubset(of: ["type", "id", "role", "status", "content", "phase"]),
            object["role"] == .string("assistant"), case .array(let parts) = object["content"]
        else {
            throw invalidItem
        }
        if let id = object["id"] {
            guard case .string(let value) = id, validIdentifier(value) else { throw invalidItem }
        }
        if let phase = object["phase"] {
            guard phase == .null || phase == .string("commentary") || phase == .string("final_answer") else {
                throw invalidItem
            }
        }
        return try parts.map { part -> String in
            guard case .object(let content) = part else { throw invalidItem }
            guard content["type"] != .string("refusal") else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.modelDeclinedRequest)
            }
            guard Set(content.keys).isSubset(of: ["type", "text", "annotations", "logprobs"]),
                content["type"] == .string("output_text"), case .string(let text) = content["text"]
            else {
                throw invalidItem
            }
            return text
        }.joined()
    }

    private static func functionCall(_ object: [String: DevelopmentJSONValue]) throws -> DevelopmentToolCall {
        guard Set(object.keys).isSubset(of: ["type", "id", "call_id", "name", "arguments", "status"]),
            case .string(let id) = object["call_id"], validIdentifier(id),
            case .string(let name) = object["name"],
            name.range(of: VyronOpenAIResponsesLimits.functionNamePattern, options: .regularExpression) != nil,
            case .string(let arguments) = object["arguments"],
            arguments.utf8.count <= VyronOpenAIResponsesLimits.argumentBytes
        else {
            throw DevelopmentAgentError.invalidTool(VyronModelDataText.serverInvalidNativeToolCall)
        }
        if let itemID = object["id"] {
            guard case .string(let value) = itemID, validIdentifier(value) else { throw invalidItem }
        }
        let values = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(arguments.utf8))
        return DevelopmentToolCall(name: name, arguments: values, id: id)
    }

    private static func validateReasoning(_ object: [String: DevelopmentJSONValue]) throws {
        guard Set(object.keys).isSubset(of: ["type", "id", "encrypted_content", "summary", "status", "content"]),
            case .string(let id) = object["id"], validIdentifier(id),
            case .string(let encrypted) = object["encrypted_content"], !encrypted.isEmpty,
            case .array(let summary) = object["summary"]
        else { throw invalidItem }
        if let content = object["content"], content != .array([]) { throw invalidItem }
        for part in summary {
            guard case .object(let value) = part,
                Set(value.keys).isSubset(of: ["type", "text"]), value["type"] == .string("summary_text"),
                case .string = value["text"]
            else { throw invalidItem }
        }
    }
}
