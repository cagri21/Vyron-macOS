import SwiftUI

struct VyronAppearanceModePicker: View {
    @Environment(VyronAppearanceState.self) private var appearance
    @Environment(\.vyronPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: VyronAppearanceSettingsStyle.modeSpacing) {
            ForEach(VyronAppearanceMode.allCases, id: \.self) { mode in
                modeButton(mode)
            }
        }
        .padding(.vertical, VyronAppearanceSettingsStyle.controlSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(VyronAppearanceText.mode)
    }

    private func modeButton(_ mode: VyronAppearanceMode) -> some View {
        let isSelected = appearance.mode == mode
        let shape = RoundedRectangle(cornerRadius: VyronSettingsStyle.rowRadius)
        return Button {
            appearance.setMode(mode)
        } label: {
            VStack(spacing: VyronAppearanceSettingsStyle.optionInset) {
                preview(for: mode)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(
                            isSelected ? palette.controlAccent : palette.border,
                            lineWidth: isSelected ? 2 : 1
                        )
                    }
                Text(verbatim: mode.title)
                    .font(VyronAppearanceSettingsStyle.modeLabel)
                    .foregroundStyle(isSelected ? palette.text : palette.muted)
            }
            .frame(width: VyronAppearanceSettingsStyle.previewWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("vyron.appearance.mode.\(mode.rawValue)")
    }

    @ViewBuilder
    private func preview(for mode: VyronAppearanceMode) -> some View {
        switch mode {
        case .system:
            HStack(spacing: 0) {
                splitPreview(for: .light)
                splitPreview(for: .dark)
            }
        case .light:
            windowPreview(for: .light)
        case .dark:
            windowPreview(for: .dark)
        }
    }

    private func splitPreview(for scheme: ColorScheme) -> some View {
        windowPreview(for: scheme)
            .frame(width: VyronAppearanceSettingsStyle.previewWidth / 2, alignment: .leading)
            .clipped()
    }

    private func windowPreview(for scheme: ColorScheme) -> some View {
        VyronAppearanceWindowPreview(palette: appearance.palette(for: scheme))
            .accessibilityHidden(true)
    }
}
