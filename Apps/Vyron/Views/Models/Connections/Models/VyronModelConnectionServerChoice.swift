import Foundation
import VyronCore

/// Named server choices are editor presentation. Saved profiles identify the protocol and endpoint.
enum VyronModelConnectionServerChoice: CaseIterable {
    case ollama
    case openAICompatible
    case anthropic
    case gemini
    case meta

    init(profile: ModelConnectionProfile) {
        switch profile.kind {
        case .ollama:
            self = .ollama
        case .anthropic:
            self = .anthropic
        case .openAICompatible:
            if VyronGeminiConnectionPreset.matches(profile) {
                self = .gemini
            } else if VyronMetaConnectionPreset.matches(profile) {
                self = .meta
            } else {
                self = .openAICompatible
            }
        }
    }

    var title: String {
        switch self {
        case .ollama: VyronAppText.settingsOllama
        case .openAICompatible: VyronAppText.settingsCompatibleAPI
        case .anthropic: ModelProviderKind.anthropic.displayName
        case .gemini: VyronGeminiConnectionPreset.name
        case .meta: VyronMetaConnectionPreset.name
        }
    }

    var isHostedPreset: Bool { self == .gemini || self == .meta }

    func applying(to current: ModelConnectionProfile) -> ModelConnectionProfile {
        let previous = Self(profile: current)
        guard self != previous else { return current }
        var updated = current
        updated.kind = kind
        if let preset = hostedPreset {
            if updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (previous.isHostedPreset && updated.name == previous.title) {
                updated.name = preset.name
            }
            updated.endpoint = preset.endpoint
            updated.selectedModel = preset.selectedModel
            return updated
        }
        if previous.isHostedPreset {
            if updated.name == previous.title { updated.name = "" }
            updated.endpoint = ""
            updated.selectedModel = ""
        }
        if self == .anthropic {
            if updated.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.endpoint = VyronClaudeConnectionPreset.endpoint
            }
            if updated.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.selectedModel = VyronClaudeConnectionPreset.defaultModel
            }
        }
        return updated
    }

    private var kind: ModelProviderKind {
        switch self {
        case .ollama: .ollama
        case .anthropic: .anthropic
        case .openAICompatible, .gemini, .meta: .openAICompatible
        }
    }

    private var hostedPreset: ModelConnectionProfile? {
        switch self {
        case .gemini: VyronGeminiConnectionPreset.makeProfile()
        case .meta: VyronMetaConnectionPreset.makeProfile()
        case .ollama, .openAICompatible, .anthropic: nil
        }
    }
}
