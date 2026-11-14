import SwiftUI

struct VyronPluginsNavigationButton: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        Button {
            model.openPlugins()
        } label: {
            HStack(spacing: VyronPluginsStyle.rowSpacing) {
                Image(systemName: VyronSymbols.plugins)
                Text(VyronPluginText.title)
                Spacer()
                Image(systemName: VyronSymbols.arrow)
                    .foregroundStyle(palette.muted)
            }
            .font(VyronPluginsStyle.action)
            .padding(VyronPluginsStyle.rowSpacing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.text)
        .padding(.horizontal, VyronPluginsStyle.compactSpacing)
        .help(VyronPluginText.subtitle)
    }
}
