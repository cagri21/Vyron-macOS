import Foundation
import VyronModelDomain

struct DevelopmentStepRequest: Encodable {
    let model: String
    let messages: [VyronOllamaDevelopmentMessage]
    let think: VyronOllamaThinkingValue?
    let tools: [DevelopmentToolDefinition]
    let stream = false
    let options: Options
    let keep_alive = "5m"
}
