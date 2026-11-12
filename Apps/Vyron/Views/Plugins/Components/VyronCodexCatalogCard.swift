import SwiftUI

struct VyronCodexCatalogCard: View {
    @Environment(\.locale) private var localizationLocale
    let isLocked: Bool
    let add: () -> Void

    var body: some View {
        let _ = localizationLocale
        Button(action: add) {
            HStack(spacing: VyronPluginsStyle.rowSpacing) {
                VyronPluginAvatar(isPenpot: false)
                VStack(alignment: .leading, spacing: VyronPluginsStyle.compactSpacing) {
                    Text(VyronPluginText.codexName)
                        .font(VyronPluginsStyle.sectionTitle).foregroundStyle(Palette.text)
                        .lineLimit(1)
                    Text(VyronPluginText.codexSummary)
                        .font(VyronPluginsStyle.body).foregroundStyle(Palette.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: VyronSymbols.plus).foregroundStyle(Palette.text)
            }
            .padding(.vertical, VyronPluginsStyle.rowSpacing)
            .frame(maxWidth: .infinity, minHeight: VyronPluginsStyle.minimumRowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }
}
