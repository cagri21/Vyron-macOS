import SwiftUI
import VyronCore

struct VyronUserInputOptionRow: View {
    @Environment(\.vyronPalette) private var palette
    let option: VyronUserInputOption
    let number: Int
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: VyronUserInputStyle.controlSpacing) {
                Text(number.formatted())
                    .font(VyronUserInputStyle.number)
                    .foregroundStyle(palette.muted)
                    .frame(width: VyronUserInputStyle.numberSize, height: VyronUserInputStyle.numberSize)
                    .background(palette.selection, in: RoundedRectangle(cornerRadius: VyronUserInputStyle.numberRadius))
                    .overlay(RoundedRectangle(cornerRadius: VyronUserInputStyle.numberRadius).stroke(palette.border))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: VyronUserInputStyle.rowSpacing) {
                    Text(verbatim: option.label)
                        .font(VyronUserInputStyle.option)
                    if !option.description.isEmpty {
                        Text(verbatim: option.description)
                            .font(VyronUserInputStyle.description)
                            .foregroundStyle(palette.muted)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: VyronUserInputStyle.numberSize, alignment: .leading)
                Image(systemName: VyronSymbols.optionArrow)
                    .font(VyronUserInputStyle.icon)
                    .foregroundStyle(palette.muted)
                    .opacity(isSelected || isHovered ? 1 : 0)
                    .frame(height: VyronUserInputStyle.numberSize)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, VyronUserInputStyle.rowHorizontalPadding)
            .padding(.vertical, VyronUserInputStyle.rowVerticalPadding)
            .background(
                isSelected || isHovered ? palette.selection : Color.clear,
                in: RoundedRectangle(cornerRadius: VyronUserInputStyle.rowRadius)
            )
            .contentShape(RoundedRectangle(cornerRadius: VyronUserInputStyle.rowRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
