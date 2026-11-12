import VyronModelDomain

struct VyronOllamaRequestMetrics: Sendable {
    let contextTokens: Int
    let outputTokens: Int
    let messageBytes: Int
    let schemaBytes: Int
}
