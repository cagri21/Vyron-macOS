public enum ModelProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ollama
    case openAICompatible
    case anthropic
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .openAICompatible: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        }
    }
}
