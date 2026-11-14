import SwiftUI

struct VyronAppearancePill<Content: View>: View {
    @Environment(\.vyronPalette) private var palette
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: VyronAppearanceSettingsStyle.controlSpacing) {
            content
        }
        .font(VyronAppearanceSettingsStyle.controlText)
        .foregroundStyle(palette.text)
        .padding(.horizontal, VyronAppearanceSettingsStyle.pillInset)
        .frame(minHeight: VyronAppearanceSettingsStyle.pillHeight)
        .background(palette.canvas, in: Capsule())
        .overlay { Capsule().strokeBorder(palette.border) }
        .contentShape(Capsule())
    }
}
