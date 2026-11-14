import SwiftUI

enum VyronAppearancePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case vyron
    case chatGPT
    case codex
    case absolutely
    case ayu
    case catppuccin
    case dracula
    case everforest
    case gitHub
    case gruvbox
    case linear
    case lobster
    case material

    var id: Self { self }

    var title: String {
        switch self {
        case .vyron: VyronAppearanceText.presetVyron
        case .chatGPT: VyronAppearanceText.presetChatGPT
        case .codex: VyronAppearanceText.presetCodex
        case .absolutely: VyronAppearanceText.presetAbsolutely
        case .ayu: VyronAppearanceText.presetAyu
        case .catppuccin: VyronAppearanceText.presetCatppuccin
        case .dracula: VyronAppearanceText.presetDracula
        case .everforest: VyronAppearanceText.presetEverforest
        case .gitHub: VyronAppearanceText.presetGitHub
        case .gruvbox: VyronAppearanceText.presetGruvbox
        case .linear: VyronAppearanceText.presetLinear
        case .lobster: VyronAppearanceText.presetLobster
        case .material: VyronAppearanceText.presetMaterial
        }
    }

    func palette(
        for scheme: ColorScheme,
        overrides: VyronAppearanceColorOverrides = VyronAppearanceColorOverrides()
    ) -> VyronAppearancePalette {
        VyronAppearancePalette(preset: self, scheme: scheme, overrides: overrides)
    }
}
