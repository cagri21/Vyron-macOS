import Foundation
import VyronModelDomain

struct VyronOllamaChatRequest: Encodable {
    let model: String
    let messages: [VyronOllamaChatMessage]
    let think: VyronOllamaThinkingValue?
    let stream = true
    let options: VyronOllamaChatOptions
    let keep_alive = "5m"
}
