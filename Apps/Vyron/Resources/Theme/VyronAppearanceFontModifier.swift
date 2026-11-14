import SwiftUI

struct VyronAppearanceFontModifier: ViewModifier {
    @Environment(\.vyronAppearanceFontFamily) private var family
    let style: VyronAppearanceTypography

    func body(content: Content) -> some View {
        content.font(style.font(family: family))
    }
}
