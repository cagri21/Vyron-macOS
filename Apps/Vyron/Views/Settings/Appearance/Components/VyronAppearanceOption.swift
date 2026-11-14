import SwiftUI

struct VyronAppearanceOption<Content: View>: View {
    @Environment(\.vyronPalette) private var palette
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let mark: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: VyronAppearanceSettingsStyle.controlSpacing) {
                mark()
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: VyronSymbols.checkmark)
                        .accessibilityHidden(true)
                }
            }
            .padding(VyronAppearanceSettingsStyle.optionInset)
            .foregroundStyle(palette.text)
            .background(
                isSelected ? palette.selection : Color.clear,
                in: RoundedRectangle(cornerRadius: VyronSettingsStyle.rowRadius)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
