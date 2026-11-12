import Foundation
import VyronModelDomain

/// Genuine provider JSON fields retain the existing memberwise transport construction boundary.
struct VyronCompatibleChatRequest: Encodable {
    let model: String
    let messages: [VyronCompatibleMessage]
    let stream: Bool
    let maxTokens: Int
    var temperature: Double? = nil
    var topP: Double? = nil
    var tools: [DevelopmentToolDefinition]? = nil
    var toolChoice: VyronCompatibleToolChoice? = nil
    var deepSeek: VyronDeepSeekRequestConfiguration? = nil

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(model, forKey: .model)
        try values.encode(messages, forKey: .messages)
        try values.encode(stream, forKey: .stream)
        try values.encode(maxTokens, forKey: .maxTokens)
        try values.encodeIfPresent(temperature, forKey: .temperature)
        try values.encodeIfPresent(topP, forKey: .topP)
        try values.encodeIfPresent(tools, forKey: .tools)
        try values.encodeIfPresent(toolChoice, forKey: .toolChoice)
        if let deepSeek {
            try values.encode(["type": deepSeek.enabled ? "enabled" : "disabled"], forKey: .thinking)
            if deepSeek.enabled { try values.encode(deepSeek.effort, forKey: .reasoningEffort) }
        }
    }
}
