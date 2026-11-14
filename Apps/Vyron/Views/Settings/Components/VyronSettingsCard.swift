import SwiftUI

struct VyronSettingsCard<Content: View>: View {
    @Environment(\.vyronPalette) private var palette
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, VyronSettingsStyle.rowInset)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronSettingsStyle.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: VyronSettingsStyle.cardRadius).stroke(palette.border)
        }
    }
}
