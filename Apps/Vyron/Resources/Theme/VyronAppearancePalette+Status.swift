import SwiftUI

extension VyronAppearancePalette {
    var success: Color {
        scheme == .dark ? VyronColors.appearanceDarkSuccess : VyronColors.appearanceLightSuccess
    }

    var warning: Color {
        scheme == .dark ? VyronColors.appearanceDarkWarning : VyronColors.appearanceLightWarning
    }

    var danger: Color {
        scheme == .dark ? VyronColors.appearanceDarkDanger : VyronColors.appearanceLightDanger
    }

    var diffAdded: Color {
        scheme == .dark ? VyronColors.appearanceDarkDiffAdded : VyronColors.appearanceLightDiffAdded
    }

    var diffRemoved: Color {
        scheme == .dark ? VyronColors.appearanceDarkDiffRemoved : VyronColors.appearanceLightDiffRemoved
    }

    var diffHunk: Color {
        scheme == .dark ? VyronColors.appearanceDarkDiffHunk : VyronColors.appearanceLightDiffHunk
    }
}
