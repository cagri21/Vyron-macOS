import SwiftUI

struct VyronPluginCatalogCard: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    let isPenpot: Bool
    let isLocked: Bool
    let add: () -> Void

    var body: some View {
        let _ = localizationLocale
        Button(action: add) {
            HStack(spacing: VyronPluginsStyle.rowSpacing) {
                VyronPluginAvatar(isPenpot: isPenpot)
                VStack(alignment: .leading, spacing: VyronPluginsStyle.compactSpacing) {
                    Text(isPenpot ? VyronPluginText.penpotName : VyronPluginText.customName)
                        .font(VyronPluginsStyle.sectionTitle).foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(isPenpot ? VyronPluginText.penpotSummary : VyronPluginText.customSummary)
                        .font(VyronPluginsStyle.body).foregroundStyle(palette.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: VyronSymbols.plus).foregroundStyle(palette.text)
            }
            .padding(.vertical, VyronPluginsStyle.rowSpacing)
            .frame(maxWidth: .infinity, minHeight: VyronPluginsStyle.minimumRowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }
}
