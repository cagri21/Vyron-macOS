import SwiftUI

extension View {
    func font(_ style: VyronAppearanceTypography) -> some View {
        modifier(VyronAppearanceFontModifier(style: style))
    }
}
