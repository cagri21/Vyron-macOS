import SwiftUI
import VyronCore

struct VyronPluginConnectionCard: View {
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var connections: MCPConnectionsModel
    @ObservedObject var presentation: VyronPluginsPresentation
    let profile: MCPConnectionProfile
    let isLocked: Bool

    private var item: VyronPluginItem { VyronPluginItem(profile: profile) }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
            Button {
                presentation.select(profile.id)
            } label: {
                HStack(alignment: .top, spacing: VyronPluginsStyle.rowSpacing) {
                    VyronPluginAvatar(isPenpot: item.isPenpot)
                    VStack(alignment: .leading, spacing: VyronPluginsStyle.compactSpacing) {
                        Text(verbatim: profile.name).font(VyronPluginsStyle.sectionTitle)
                            .foregroundStyle(Palette.text)
                        Text(verbatim: item.address).font(VyronPluginsStyle.caption)
                            .foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: VyronSymbols.arrow).foregroundStyle(Palette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(VyronPluginText.details)

            HStack {
                HStack(spacing: VyronPluginsStyle.compactSpacing) {
                    Circle()
                        .fill(connections.isConnected(profile.id) ? Palette.success : Palette.muted)
                        .frame(width: VyronPluginsStyle.statusSize, height: VyronPluginsStyle.statusSize)
                    Text(verbatim: status)
                        .font(VyronPluginsStyle.caption).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                VyronPluginConnectionActions(
                    connections: connections,
                    presentation: presentation,
                    profile: profile,
                    isLocked: isLocked
                )
            }
        }
        .padding(VyronPluginsStyle.cardPadding)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: VyronPluginsStyle.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: VyronPluginsStyle.cardRadius).stroke(Palette.border))
    }

    private var status: String {
        guard profile.enabled else { return VyronPluginText.disabled }
        return connections.statuses[profile.id] ?? VyronPluginText.ready
    }
}
