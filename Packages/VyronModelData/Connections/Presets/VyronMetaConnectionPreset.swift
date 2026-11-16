import VyronModelDomain

/// Draft for Meta Model API's OpenAI-compatible Chat Completions API.
public enum VyronMetaConnectionPreset {
    public static let name = "Meta"
    public static let endpoint = "https://api.meta.ai/v1"
    public static let defaultModel = "muse-spark-1.3"

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
