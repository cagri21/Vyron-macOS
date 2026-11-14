import SwiftUI
import VyronCore

struct VyronPluginInstalledRow: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var connections: MCPConnectionsModel
    @ObservedObject var presentation: VyronPluginsPresentation
    let profile: MCPConnectionProfile
    let isLocked: Bool

    private var item: VyronPluginItem { VyronPluginItem(profile: profile) }
    private var isBusy: Bool { connections.busy.contains(profile.id) }
    private var status: String {
        guard profile.enabled else { return VyronPluginText.disabled }
        return connections.statuses[profile.id] ?? VyronPluginText.ready
    }

    var body: some View {
        let _ = localizationLocale
        HStack(spacing: VyronPluginsStyle.rowSpacing) {
            Button { presentation.select(profile.id) } label: {
                HStack(spacing: VyronPluginsStyle.rowSpacing) {
                    VyronPluginAvatar(isPenpot: item.isPenpot)
                    VStack(alignment: .leading, spacing: VyronPluginsStyle.compactSpacing) {
                        Text(verbatim: profile.name).font(VyronPluginsStyle.sectionTitle)
                            .foregroundStyle(palette.text).lineLimit(1)
                        Text(verbatim: status).font(VyronPluginsStyle.body)
                            .foregroundStyle(palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(VyronPluginText.details)
            if isBusy { ProgressView().controlSize(.small) }
            actions
        }
        .padding(.vertical, VyronPluginsStyle.rowSpacing)
        .frame(maxWidth: .infinity, minHeight: VyronPluginsStyle.minimumRowHeight, alignment: .leading)
    }

    private var actions: some View {
        Menu {
            Button(VyronPluginText.details) { presentation.select(profile.id) }
            if isBusy {
                Button(VyronPluginText.cancel) { connections.disconnect(profile.id) }
            } else if connections.isConnected(profile.id) {
                Button(VyronPluginText.disconnect) { connections.disconnect(profile.id) }
            } else {
                Button(VyronPluginText.connect) { connections.connect(profile) }
                    .disabled(!profile.enabled)
            }
            Divider()
            Button(VyronPluginText.edit) { presentation.editingProfile = profile }
                .disabled(isBusy)
            Button(profile.enabled ? VyronPluginText.disable : VyronPluginText.enable) {
                connections.setEnabled(!profile.enabled, for: profile)
            }
            .disabled(isBusy)
            Button(VyronPluginText.remove, role: .destructive) { presentation.removingProfile = profile }
                .disabled(isBusy)
        } label: {
            Image(systemName: VyronSymbols.ellipsis)
                .font(VyronPluginsStyle.sectionTitle)
                .frame(width: VyronPluginsStyle.toolbarControlSize, height: VyronPluginsStyle.toolbarControlSize)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(palette.text).disabled(isLocked)
        .help(VyronPluginText.details).accessibilityLabel(VyronPluginText.details)
    }
}
