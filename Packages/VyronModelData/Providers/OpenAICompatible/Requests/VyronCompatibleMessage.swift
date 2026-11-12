import Foundation
import VyronLocalization
import VyronModelDomain

/// Exact Chat Completions JSON representation; optional wire fields are a transport boundary exception.
struct VyronCompatibleMessage: Codable {
    let role: String
    let content: String?
    var toolCalls: [VyronCompatibleToolCall]? = nil
    var toolCallID: String? = nil
    var images: [VyronImageAttachment]? = nil
    var reasoningContent: String? = nil

    init(role: String, content: String?) {
        self.role = role
        self.content = content
    }

    init(_ message: DevelopmentMessage, scope: VyronDeepSeekReplayScope? = nil) throws {
        role = message.role
        content = message.content
        images = message.images
        toolCalls = try message.toolCalls.map { try $0.map(VyronCompatibleToolCall.init) }
        reasoningContent = try scope?.reasoning(for: message)
        if role == "tool" {
            guard let id = message.toolCallID, !id.isEmpty else {
                throw DevelopmentAgentError.invalidTool(VyronModelDataText.missingToolResultAssociation)
            }
            toolCallID = id
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        role = try values.decode(String.self, forKey: .role)
        content = try values.decodeIfPresent(String.self, forKey: .content)
        toolCalls = try values.decodeIfPresent([VyronCompatibleToolCall].self, forKey: .toolCalls)
        toolCallID = try values.decodeIfPresent(String.self, forKey: .toolCallID)
        reasoningContent = try values.decodeIfPresent(String.self, forKey: .reasoningContent)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(role, forKey: .role)
        if let images, !images.isEmpty {
            var parts: [DevelopmentJSONValue] = [
                .object(["type": .string("text"), "text": .string(content ?? "")])
            ]
            parts += images.map { image in
                .object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string("data:\(image.mimeType);base64,\(image.data.base64EncodedString())")
                    ])
                ])
            }
            try values.encode(parts, forKey: .content)
        } else {
            try values.encodeIfPresent(content, forKey: .content)
        }
        try values.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try values.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try values.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
    }
}
