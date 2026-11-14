import SwiftUI

struct VyronAppearanceStatusColorsView: View {
    @Environment(\.vyronPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: VyronSettingsStyle.textSpacing) {
            Text(VyronAppearanceText.statusColors)
                .font(VyronSettingsStyle.sectionTitle)
                .foregroundStyle(palette.text)
                .accessibilityAddTraits(.isHeader)
            VyronSettingsCard {
                Grid(horizontalSpacing: VyronSettingsStyle.rowSpacing, verticalSpacing: 0) {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        columnHeading(VyronAppearanceText.light)
                        columnHeading(VyronAppearanceText.dark)
                    }
                    statusRow(.success)
                    separator
                    statusRow(.warning)
                    separator
                    statusRow(.danger)
                    separator
                    statusRow(.fullAccess)
                }
                .padding(.top, VyronAppearanceSettingsStyle.controlSpacing)
            }
        }
    }

    private func columnHeading(_ title: String) -> some View {
        Text(title)
            .font(VyronAppearanceSettingsStyle.modeLabel)
            .foregroundStyle(palette.muted)
            .accessibilityHidden(true)
    }

    private func statusRow(_ slot: VyronAppearanceColorSlot) -> some View {
        GridRow {
            Text(slot.title)
                .font(VyronSettingsStyle.body)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: VyronAppearanceSettingsStyle.rowHeight)
                .accessibilityHidden(true)
            VyronAppearanceColorControl(slot: slot, scheme: .light)
            VyronAppearanceColorControl(slot: slot, scheme: .dark)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: VyronSettingsStyle.dividerWidth)
            .gridCellColumns(3)
            .gridCellUnsizedAxes(.horizontal)
            .accessibilityHidden(true)
    }
}
