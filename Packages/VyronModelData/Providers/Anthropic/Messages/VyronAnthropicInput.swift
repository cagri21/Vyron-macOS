import VyronModelDomain

struct VyronAnthropicInput: Sendable {
    var system: [DevelopmentJSONValue] = []
    var messages: [DevelopmentJSONValue] = []
}
