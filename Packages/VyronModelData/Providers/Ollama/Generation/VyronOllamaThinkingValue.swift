import VyronModelDomain

/// Ollama's `think` transport value is a JSON boolean or advertised level string.
enum VyronOllamaThinkingValue: Encodable {
    case toggle(VyronOllamaThinkingToggle)
    case level(VyronModelThinkingLevel)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .toggle(let toggle):
            try container.encode(toggle.value)
        case .level(let level):
            try container.encode(level.rawValue)
        }
    }
}
