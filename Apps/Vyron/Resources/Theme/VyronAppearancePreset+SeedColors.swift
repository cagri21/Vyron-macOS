import SwiftUI

extension VyronAppearancePreset {
    func seedColors(for scheme: ColorScheme) -> VyronAppearanceSeedColors {
        scheme == .dark ? darkColors : lightColors
    }

    private var lightColors: VyronAppearanceSeedColors {
        switch self {
        case .vyron:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceVyronLightBackground,
                foreground: VyronColors.appearanceVyronLightForeground,
                accent: VyronColors.appearanceVyronLightAccent
            )
        case .chatGPT:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceChatGptLightBackground,
                foreground: VyronColors.appearanceChatGptLightForeground,
                accent: VyronColors.appearanceChatGptLightAccent
            )
        case .codex:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceCodexLightBackground,
                foreground: VyronColors.appearanceCodexLightForeground,
                accent: VyronColors.appearanceCodexLightAccent
            )
        case .absolutely:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceAbsolutelyLightBackground,
                foreground: VyronColors.appearanceAbsolutelyLightForeground,
                accent: VyronColors.appearanceAbsolutelyLightAccent
            )
        case .ayu:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceAyuLightBackground,
                foreground: VyronColors.appearanceAyuLightForeground,
                accent: VyronColors.appearanceAyuLightAccent
            )
        case .catppuccin:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceCatppuccinLightBackground,
                foreground: VyronColors.appearanceCatppuccinLightForeground,
                accent: VyronColors.appearanceCatppuccinLightAccent
            )
        case .dracula:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceDraculaLightBackground,
                foreground: VyronColors.appearanceDraculaLightForeground,
                accent: VyronColors.appearanceDraculaLightAccent
            )
        case .everforest:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceEverforestLightBackground,
                foreground: VyronColors.appearanceEverforestLightForeground,
                accent: VyronColors.appearanceEverforestLightAccent
            )
        case .gitHub:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceGitHubLightBackground,
                foreground: VyronColors.appearanceGitHubLightForeground,
                accent: VyronColors.appearanceGitHubLightAccent
            )
        case .gruvbox:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceGruvboxLightBackground,
                foreground: VyronColors.appearanceGruvboxLightForeground,
                accent: VyronColors.appearanceGruvboxLightAccent
            )
        case .linear:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceLinearLightBackground,
                foreground: VyronColors.appearanceLinearLightForeground,
                accent: VyronColors.appearanceLinearLightAccent
            )
        case .lobster:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceLobsterLightBackground,
                foreground: VyronColors.appearanceLobsterLightForeground,
                accent: VyronColors.appearanceLobsterLightAccent
            )
        case .material:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceMaterialLightBackground,
                foreground: VyronColors.appearanceMaterialLightForeground,
                accent: VyronColors.appearanceMaterialLightAccent
            )
        }
    }

    private var darkColors: VyronAppearanceSeedColors {
        switch self {
        case .vyron:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceVyronDarkBackground,
                foreground: VyronColors.appearanceVyronDarkForeground,
                accent: VyronColors.appearanceVyronDarkAccent
            )
        case .chatGPT:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceChatGptDarkBackground,
                foreground: VyronColors.appearanceChatGptDarkForeground,
                accent: VyronColors.appearanceChatGptDarkAccent
            )
        case .codex:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceCodexDarkBackground,
                foreground: VyronColors.appearanceCodexDarkForeground,
                accent: VyronColors.appearanceCodexDarkAccent
            )
        case .absolutely:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceAbsolutelyDarkBackground,
                foreground: VyronColors.appearanceAbsolutelyDarkForeground,
                accent: VyronColors.appearanceAbsolutelyDarkAccent
            )
        case .ayu:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceAyuDarkBackground,
                foreground: VyronColors.appearanceAyuDarkForeground,
                accent: VyronColors.appearanceAyuDarkAccent
            )
        case .catppuccin:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceCatppuccinDarkBackground,
                foreground: VyronColors.appearanceCatppuccinDarkForeground,
                accent: VyronColors.appearanceCatppuccinDarkAccent
            )
        case .dracula:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceDraculaDarkBackground,
                foreground: VyronColors.appearanceDraculaDarkForeground,
                accent: VyronColors.appearanceDraculaDarkAccent
            )
        case .everforest:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceEverforestDarkBackground,
                foreground: VyronColors.appearanceEverforestDarkForeground,
                accent: VyronColors.appearanceEverforestDarkAccent
            )
        case .gitHub:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceGitHubDarkBackground,
                foreground: VyronColors.appearanceGitHubDarkForeground,
                accent: VyronColors.appearanceGitHubDarkAccent
            )
        case .gruvbox:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceGruvboxDarkBackground,
                foreground: VyronColors.appearanceGruvboxDarkForeground,
                accent: VyronColors.appearanceGruvboxDarkAccent
            )
        case .linear:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceLinearDarkBackground,
                foreground: VyronColors.appearanceLinearDarkForeground,
                accent: VyronColors.appearanceLinearDarkAccent
            )
        case .lobster:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceLobsterDarkBackground,
                foreground: VyronColors.appearanceLobsterDarkForeground,
                accent: VyronColors.appearanceLobsterDarkAccent
            )
        case .material:
            VyronAppearanceSeedColors(
                background: VyronColors.appearanceMaterialDarkBackground,
                foreground: VyronColors.appearanceMaterialDarkForeground,
                accent: VyronColors.appearanceMaterialDarkAccent
            )
        }
    }
}
