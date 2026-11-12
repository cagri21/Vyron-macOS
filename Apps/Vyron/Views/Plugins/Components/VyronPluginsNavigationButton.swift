import SwiftUI

struct VyronPluginsNavigationButton: View {
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
                    .foregroundStyle(Palette.muted)
            }
            .font(VyronPluginsStyle.action)
            .padding(VyronPluginsStyle.rowSpacing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.text)
        .padding(.horizontal, VyronPluginsStyle.compactSpacing)
        .help(VyronPluginText.subtitle)
    }
}
