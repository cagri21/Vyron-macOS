import Foundation
import VyronModelDomain

struct VyronOllamaChatRequest: Encodable {
    let model: String
    let messages: [VyronOllamaChatMessage]
    let think: VyronOllamaThinkingValue?
    let format: VyronOllamaChatFormat?
    let stream = true
    let options: VyronOllamaChatOptions
    let keep_alive = "5m"

    // This DTO preserves Ollama's flat JSON fields; related generation controls share one construction input.
    init(model: String, messages: [VyronOllamaChatMessage], generation: VyronOllamaChatGeneration) {
        self.model = model
        self.messages = messages
        think = generation.think
        format = generation.format
        options = generation.options
    }
}
