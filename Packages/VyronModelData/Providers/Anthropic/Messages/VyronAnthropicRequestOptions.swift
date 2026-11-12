import VyronModelDomain

struct VyronAnthropicRequestOptions: Sendable {
    var maximumOutputTokens: Int? = nil
    var stream = false
    var tools: [DevelopmentJSONValue] = []
}
