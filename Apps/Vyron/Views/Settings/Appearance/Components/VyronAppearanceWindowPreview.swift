import SwiftUI

struct VyronAppearanceWindowPreview: View {
    let palette: VyronAppearancePalette

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            chat
        }
        .background(palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: VyronAppearanceSettingsStyle.previewWindowRadius))
        .overlay {
            RoundedRectangle(cornerRadius: VyronAppearanceSettingsStyle.previewWindowRadius)
                .strokeBorder(palette.border)
        }
        .padding(VyronAppearanceSettingsStyle.previewInset)
        .frame(width: VyronAppearanceSettingsStyle.previewWidth, height: VyronAppearanceSettingsStyle.previewHeight)
        .background(palette.raised)
    }

    private var sidebar: some View {
        VStack(spacing: VyronAppearanceSettingsStyle.previewLineSpacing) {
            Circle()
                .fill(palette.muted)
                .frame(width: 4, height: 4)
            line(width: 5, color: palette.border, alignment: .center)
            Spacer(minLength: 0)
        }
        .padding(.vertical, VyronAppearanceSettingsStyle.previewWindowRadius)
        .frame(width: VyronAppearanceSettingsStyle.previewSidebarWidth)
        .background(palette.surface)
    }

    private var chat: some View {
        VStack(spacing: VyronAppearanceSettingsStyle.previewLineSpacing) {
            line(width: 23, color: palette.controlAccent, alignment: .trailing)
            line(width: 20, color: palette.muted.opacity(0.5), alignment: .leading)
            line(width: 30, color: palette.muted.opacity(0.5), alignment: .leading)
            line(width: 17, color: palette.controlAccent, alignment: .trailing)
            Capsule()
                .strokeBorder(palette.muted.opacity(0.45))
                .frame(height: 5)
        }
        .padding(VyronAppearanceSettingsStyle.previewWindowRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func line(width: CGFloat, color: Color, alignment: Alignment) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: VyronAppearanceSettingsStyle.previewLineHeight)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}
