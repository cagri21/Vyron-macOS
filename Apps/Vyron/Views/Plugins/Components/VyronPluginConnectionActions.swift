import SwiftUI
import VyronCore

struct VyronPluginConnectionActions: View {
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var connections: MCPConnectionsModel
    @ObservedObject var presentation: VyronPluginsPresentation
    let profile: MCPConnectionProfile
    let isLocked: Bool

    var body: some View {
        let _ = localizationLocale
        HStack(spacing: VyronPluginsStyle.compactSpacing) {
            if connections.busy.contains(profile.id) {
                ProgressView().controlSize(.small)
                Button(VyronPluginText.cancel) { connections.disconnect(profile.id) }
                    .buttonStyle(QuietButtonStyle(foreground: Palette.text))
            } else if connections.isConnected(profile.id) {
                Button(VyronPluginText.disconnect) { connections.disconnect(profile.id) }
                    .buttonStyle(QuietButtonStyle(foreground: Palette.text))
            } else {
                Button(VyronPluginText.connect) { connections.connect(profile) }
                    .buttonStyle(QuietButtonStyle(foreground: Palette.text))
                    .disabled(!profile.enabled)
            }

            Menu {
                Button(VyronPluginText.edit) { presentation.editingProfile = profile }
                    .disabled(connections.busy.contains(profile.id))
                Button(profile.enabled ? VyronPluginText.disable : VyronPluginText.enable) {
                    connections.setEnabled(!profile.enabled, for: profile)
                }
                .disabled(connections.busy.contains(profile.id))
                Divider()
                Button(VyronPluginText.remove, role: .destructive) { presentation.removingProfile = profile }
            } label: {
                Image(systemName: VyronSymbols.ellipsis)
                    .font(VyronPluginsStyle.emphasizedActionGlyph)
                    .foregroundStyle(Palette.text)
                    .padding(VyronPluginsStyle.compactSpacing)
            }
            .menuStyle(.borderlessButton)
            .tint(Palette.text)
            .font(VyronPluginsStyle.emphasizedAction)
            .fixedSize()
            .help(VyronPluginText.details)
        }
        .font(VyronPluginsStyle.emphasizedAction)
        .disabled(isLocked)
    }
}
