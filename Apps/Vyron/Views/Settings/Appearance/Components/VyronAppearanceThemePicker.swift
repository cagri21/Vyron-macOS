import SwiftUI

struct VyronAppearanceThemePicker: View {
    @Environment(VyronAppearanceState.self) private var appearance
    @Environment(\.vyronPalette) private var palette
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            VyronAppearancePill {
                mark(palette)
                Text(verbatim: appearance.preset.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: VyronSymbols.chevronDown)
                    .font(VyronAppearanceSettingsStyle.chevron)
                    .foregroundStyle(palette.muted)
            }
            .frame(width: VyronAppearanceSettingsStyle.pickerLabelWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VyronAppearanceText.theme)
        .accessibilityValue(appearance.preset.title)
        .accessibilityIdentifier("vyron.appearance.theme")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: VyronAppearanceSettingsStyle.optionInset) {
                    option(.vyron)
                    option(.chatGPT)
                    Divider()
                    Text(VyronAppearanceText.codexThemes)
                        .font(VyronAppearanceSettingsStyle.modeLabel)
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, VyronAppearanceSettingsStyle.optionInset)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(VyronAppearancePreset.allCases.filter { $0 != .vyron && $0 != .chatGPT }, id: \.self) {
                        option($0)
                    }
                }
                .padding(VyronAppearanceSettingsStyle.popoverInset)
            }
            .frame(
                width: VyronAppearanceSettingsStyle.popoverWidth,
                height: VyronAppearanceSettingsStyle.popoverListHeight
            )
        }
    }

    private func option(_ preset: VyronAppearancePreset) -> some View {
        VyronAppearanceOption(title: preset.title, isSelected: appearance.preset == preset) {
            appearance.selectPreset(preset)
            isOpen = false
        } mark: {
            mark(preset.palette(for: palette.scheme))
        }
    }

    private func mark(_ theme: VyronAppearancePalette) -> some View {
        Circle()
            .fill(theme.canvas)
            .overlay { Circle().strokeBorder(theme.border) }
            .overlay {
                Image(systemName: VyronSymbols.appearanceSample)
                    .font(VyronAppearanceSettingsStyle.themeMark)
                    .foregroundStyle(theme.controlAccent)
            }
            .frame(
                width: VyronAppearanceSettingsStyle.themeMarkSize,
                height: VyronAppearanceSettingsStyle.themeMarkSize
            )
            .accessibilityHidden(true)
    }
}
