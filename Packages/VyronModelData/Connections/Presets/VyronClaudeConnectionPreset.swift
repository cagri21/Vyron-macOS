import VyronModelDomain

public enum VyronClaudeConnectionPreset {
    public static let endpoint = "https://api.anthropic.com/v1"
    public static let defaultModel = "claude-sonnet-5-5"

    public static func makeProfile() -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Claude",
            kind: .anthropic,
            endpoint: endpoint,
            selectedModel: defaultModel
        )
    }
}
