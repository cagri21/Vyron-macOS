import Foundation
import VyronModelDomain

/// Ollama uses base64 image strings, while saved semantic messages retain typed attachments.
struct VyronOllamaDevelopmentMessage: Encodable {
    let message: DevelopmentMessage

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(message.role, forKey: .role)
        try values.encode(message.content, forKey: .content)
        try values.encodeIfPresent(message.toolCalls, forKey: .toolCalls)
        try values.encodeIfPresent(message.toolName, forKey: .toolName)
        try values.encodeIfPresent(message.toolCallID, forKey: .toolCallID)
        if let images = message.images, !images.isEmpty {
            try values.encode(images.map { $0.data.base64EncodedString() }, forKey: .images)
        }
    }
}
