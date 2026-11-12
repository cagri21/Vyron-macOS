import VyronModelDomain

public enum VyronOpenAIConnectionPreset {
    public static func makeProfile() -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "OpenAI",
            kind: .openAICompatible,
            endpoint: VyronOpenAIResponsesRoute.endpoint,
            selectedModel: VyronOpenAIResponsesModelFamily.gpt61Sol.rawValue
        )
    }
}
