import SwiftUI

extension VyronAppearancePreset {
    func statusColors(for scheme: ColorScheme) -> VyronAppearanceStatusColors {
        switch (self, scheme == .dark) {
        case (.vyron, true), (.codex, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceDarkSuccess,
                warning: VyronColors.appearanceDarkWarning,
                danger: VyronColors.appearanceDarkDanger,
                fullAccess: VyronColors.appearanceDarkWarning
            )
        case (.chatGPT, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceChatGptDarkSuccess,
                warning: VyronColors.appearanceChatGptDarkWarning,
                danger: VyronColors.appearanceChatGptDarkDanger,
                fullAccess: VyronColors.appearanceChatGptDarkFullAccess
            )
        case (.absolutely, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceAbsolutelyDarkSuccess,
                warning: VyronColors.appearanceAbsolutelyDarkWarning,
                danger: VyronColors.appearanceAbsolutelyDarkDanger,
                fullAccess: VyronColors.appearanceAbsolutelyDarkFullAccess
            )
        case (.ayu, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceAyuDarkSuccess,
                warning: VyronColors.appearanceAyuDarkWarning,
                danger: VyronColors.appearanceAyuDarkDanger,
                fullAccess: VyronColors.appearanceAyuDarkFullAccess
            )
        case (.catppuccin, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceCatppuccinDarkSuccess,
                warning: VyronColors.appearanceCatppuccinDarkWarning,
                danger: VyronColors.appearanceCatppuccinDarkDanger,
                fullAccess: VyronColors.appearanceCatppuccinDarkFullAccess
            )
        case (.dracula, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceDraculaDarkSuccess,
                warning: VyronColors.appearanceDraculaDarkWarning,
                danger: VyronColors.appearanceDraculaDarkDanger,
                fullAccess: VyronColors.appearanceDraculaDarkFullAccess
            )
        case (.everforest, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceEverforestDarkSuccess,
                warning: VyronColors.appearanceEverforestDarkWarning,
                danger: VyronColors.appearanceEverforestDarkDanger,
                fullAccess: VyronColors.appearanceEverforestDarkFullAccess
            )
        case (.gitHub, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceGitHubDarkSuccess,
                warning: VyronColors.appearanceGitHubDarkWarning,
                danger: VyronColors.appearanceGitHubDarkDanger,
                fullAccess: VyronColors.appearanceGitHubDarkFullAccess
            )
        case (.gruvbox, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceGruvboxDarkSuccess,
                warning: VyronColors.appearanceGruvboxDarkWarning,
                danger: VyronColors.appearanceGruvboxDarkDanger,
                fullAccess: VyronColors.appearanceGruvboxDarkFullAccess
            )
        case (.linear, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceLinearDarkSuccess,
                warning: VyronColors.appearanceLinearDarkWarning,
                danger: VyronColors.appearanceLinearDarkDanger,
                fullAccess: VyronColors.appearanceLinearDarkFullAccess
            )
        case (.lobster, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceLobsterDarkSuccess,
                warning: VyronColors.appearanceLobsterDarkWarning,
                danger: VyronColors.appearanceLobsterDarkDanger,
                fullAccess: VyronColors.appearanceLobsterDarkFullAccess
            )
        case (.material, true):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceMaterialDarkSuccess,
                warning: VyronColors.appearanceMaterialDarkWarning,
                danger: VyronColors.appearanceMaterialDarkDanger,
                fullAccess: VyronColors.appearanceMaterialDarkFullAccess
            )
        case (.vyron, false), (.codex, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceLightSuccess,
                warning: VyronColors.appearanceLightWarning,
                danger: VyronColors.appearanceLightDanger,
                fullAccess: VyronColors.appearanceLightWarning
            )
        case (.chatGPT, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceChatGptLightSuccess,
                warning: VyronColors.appearanceChatGptLightWarning,
                danger: VyronColors.appearanceChatGptLightDanger,
                fullAccess: VyronColors.appearanceChatGptLightFullAccess
            )
        case (.absolutely, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceAbsolutelyLightSuccess,
                warning: VyronColors.appearanceAbsolutelyLightWarning,
                danger: VyronColors.appearanceAbsolutelyLightDanger,
                fullAccess: VyronColors.appearanceAbsolutelyLightFullAccess
            )
        case (.ayu, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceAyuLightSuccess,
                warning: VyronColors.appearanceAyuLightWarning,
                danger: VyronColors.appearanceAyuLightDanger,
                fullAccess: VyronColors.appearanceAyuLightFullAccess
            )
        case (.catppuccin, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceCatppuccinLightSuccess,
                warning: VyronColors.appearanceCatppuccinLightWarning,
                danger: VyronColors.appearanceCatppuccinLightDanger,
                fullAccess: VyronColors.appearanceCatppuccinLightFullAccess
            )
        case (.dracula, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceDraculaLightSuccess,
                warning: VyronColors.appearanceDraculaLightWarning,
                danger: VyronColors.appearanceDraculaLightDanger,
                fullAccess: VyronColors.appearanceDraculaLightFullAccess
            )
        case (.everforest, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceEverforestLightSuccess,
                warning: VyronColors.appearanceEverforestLightWarning,
                danger: VyronColors.appearanceEverforestLightDanger,
                fullAccess: VyronColors.appearanceEverforestLightFullAccess
            )
        case (.gitHub, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceGitHubLightSuccess,
                warning: VyronColors.appearanceGitHubLightWarning,
                danger: VyronColors.appearanceGitHubLightDanger,
                fullAccess: VyronColors.appearanceGitHubLightFullAccess
            )
        case (.gruvbox, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceGruvboxLightSuccess,
                warning: VyronColors.appearanceGruvboxLightWarning,
                danger: VyronColors.appearanceGruvboxLightDanger,
                fullAccess: VyronColors.appearanceGruvboxLightFullAccess
            )
        case (.linear, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceLinearLightSuccess,
                warning: VyronColors.appearanceLinearLightWarning,
                danger: VyronColors.appearanceLinearLightDanger,
                fullAccess: VyronColors.appearanceLinearLightFullAccess
            )
        case (.lobster, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceLobsterLightSuccess,
                warning: VyronColors.appearanceLobsterLightWarning,
                danger: VyronColors.appearanceLobsterLightDanger,
                fullAccess: VyronColors.appearanceLobsterLightFullAccess
            )
        case (.material, false):
            VyronAppearanceStatusColors(
                success: VyronColors.appearanceMaterialLightSuccess,
                warning: VyronColors.appearanceMaterialLightWarning,
                danger: VyronColors.appearanceMaterialLightDanger,
                fullAccess: VyronColors.appearanceMaterialLightFullAccess
            )
        }
    }
}
