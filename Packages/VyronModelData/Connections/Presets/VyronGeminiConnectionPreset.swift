import VyronModelDomain

/// Draft for Gemini's OpenAI-compatible Chat Completions API.
public enum VyronGeminiConnectionPreset {
    public static let name = "Gemini"
    public static let endpoint = "https://generativelanguage.googleapis.com/v1beta/openai"
    public static let defaultModel = "gemini-3.8-flash"

    public static func makeProfile() -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: name,
            kind: .openAICompatible,
            endpoint: endpoint,
            selectedModel: defaultModel
        )
    }

    public static func matches(_ profile: ModelConnectionProfile) -> Bool {
        ModelEndpoint.matchesOfficialCompatibleEndpoint(endpoint, profile: profile)
    }
}
