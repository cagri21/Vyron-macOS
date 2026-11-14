import SwiftUI

struct VyronAppearanceScope: ViewModifier {
    @Environment(\.colorScheme) private var systemScheme
    let appearance: VyronAppearanceState

    func body(content: Content) -> some View {
        let preferredScheme = appearance.mode.preferredColorScheme
        content
            .font(appearance.fontFamily.map { VyronAppearanceTypography.body.font(family: $0) })
            .environment(\.vyronAppearanceFontFamily, appearance.fontFamily)
            .environment(\.vyronPalette, appearance.palette(for: preferredScheme ?? systemScheme))
            .environment(appearance)
            .preferredColorScheme(preferredScheme)
    }
}
