import Foundation
import VyronModelDomain

/// Creates a draft using the existing connection and credential identities.
/// Selecting a preset does not save a connection or make a model request.
public enum VyronDeepSeekConnectionPreset {
    public static func makeProfile() -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "DeepSeek",
            kind: .openAICompatible,
            endpoint: VyronDeepSeekRoute.endpoint,
            selectedModel: VyronDeepSeekRoute.defaultModel
        )
    }
}
