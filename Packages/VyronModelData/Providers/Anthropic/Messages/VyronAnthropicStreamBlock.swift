import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronAnthropicStreamBlock {
    private(set) var fields: [String: DevelopmentJSONValue]
    private var partialArguments = ""

    init(fields: [String: DevelopmentJSONValue]) {
        self.fields = fields
    }

    var visibleText: String {
        guard fields["type"] == .string("text"), case .string(let text) = fields["text"] else { return "" }
        return text
    }

    mutating func append(_ delta: [String: DevelopmentJSONValue]) throws -> String {
        switch delta["type"] {
        case .string("text_delta"):
            guard fields["type"] == .string("text"), case .string(let text) = delta["text"] else { throw invalidDelta }
            try appendField("text", text)
            return text
        case .string("input_json_delta"):
            guard fields["type"] == .string("tool_use"), case .string(let partial) = delta["partial_json"] else {
                throw invalidDelta
            }
            guard partialArguments.utf8.count + partial.utf8.count <= VyronAnthropicWire.maximumArgumentBytes else {
                throw DevelopmentAgentError.invalidTool(VyronModelDataText.claudeToolArgumentsTooLarge)
            }
            partialArguments += partial
        case .string("thinking_delta"):
            guard fields["type"] == .string("thinking"), case .string(let thinking) = delta["thinking"] else {
                throw invalidDelta
            }
            try appendField("thinking", thinking)
        case .string("signature_delta"):
            guard fields["type"] == .string("thinking"), case .string(let signature) = delta["signature"] else {
                throw invalidDelta
            }
            try appendField("signature", signature)
        default:
            break
        }
        return ""
    }

    func completedContent() throws -> DevelopmentJSONValue {
        guard !partialArguments.isEmpty else { return .object(fields) }
        guard fields["input"] == .object([:]) else { throw invalidDelta }
        let arguments: [String: DevelopmentJSONValue]
        do {
            arguments = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(partialArguments.utf8))
        } catch {
            throw DevelopmentAgentError.invalidTool(VyronModelDataText.claudeInvalidToolArguments)
        }
        var completed = fields
        completed["input"] = .object(arguments)
        return .object(completed)
    }

    private var invalidDelta: ModelProviderError {
        .invalidResponse(VyronModelDataText.claudeInvalidStreamContent)
    }

    private mutating func appendField(_ field: String, _ delta: String) throws {
        let existing: String
        switch fields[field] {
        case nil: existing = ""
        case .string(let value): existing = value
        default: throw invalidDelta
        }
        guard existing.utf8.count + delta.utf8.count <= VyronAnthropicWire.maximumResponseBytes else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.claudeResponseTooLarge)
        }
        fields[field] = .string(existing + delta)
    }
}
