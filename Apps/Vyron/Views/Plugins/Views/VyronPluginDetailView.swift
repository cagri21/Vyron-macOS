import SwiftUI
import VyronCore

struct VyronPluginDetailView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @ObservedObject var connections: MCPConnectionsModel
    @ObservedObject var presentation: VyronPluginsPresentation
    let profile: MCPConnectionProfile

    private var item: VyronPluginItem { VyronPluginItem(profile: profile) }
    private var isLocked: Bool { !model.canManageMCPConnections }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronPluginsStyle.sectionSpacing) {
            Button {
                presentation.showAll()
            } label: {
                Label(VyronPluginText.backToAll, systemImage: VyronSymbols.back)
            }
            .buttonStyle(.plain)
            .font(VyronPluginsStyle.action)
            .foregroundStyle(palette.muted)

            HStack(spacing: VyronPluginsStyle.rowSpacing) {
                VyronPluginAvatar(isPenpot: item.isPenpot)
                VStack(alignment: .leading, spacing: VyronPluginsStyle.compactSpacing) {
                    Text(verbatim: profile.name).font(VyronPluginsStyle.title)
                    Text(verbatim: connections.statuses[profile.id] ?? VyronPluginText.ready)
                        .font(VyronPluginsStyle.body).foregroundStyle(palette.muted)
                }
                Spacer()
                VyronPluginConnectionActions(
                    connections: connections,
                    presentation: presentation,
                    profile: profile,
                    isLocked: isLocked
                )
            }

            VStack(alignment: .leading, spacing: VyronPluginsStyle.cardPadding) {
                Text(VyronPluginText.details).font(VyronPluginsStyle.sectionTitle)
                LabeledContent(item.transportTitle) {
                    Text(verbatim: item.address).font(VyronPluginsStyle.code).textSelection(.enabled)
                }
                LabeledContent(VyronPluginText.enabled) {
                    Toggle(
                        VyronPluginText.enabled,
                        isOn: Binding(
                            get: { profile.enabled },
                            set: { connections.setEnabled($0, for: profile) }
                        )
                    )
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(isLocked || connections.busy.contains(profile.id))
                }
                Label(item.permissionTitle, systemImage: VyronSymbols.hand)
                    .foregroundStyle(palette.muted)
                Button(VyronPluginText.edit) { presentation.editingProfile = profile }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(isLocked || connections.busy.contains(profile.id))
            }
            .font(VyronPluginsStyle.body)
            .padding(VyronPluginsStyle.cardPadding)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronPluginsStyle.cardRadius))

            VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
                Text(VyronPluginText.toolsTitle).font(VyronPluginsStyle.sectionTitle)
                if let tools = connections.tools[profile.id], !tools.isEmpty {
                    ForEach(tools) { tool in
                        VyronPluginToolRow(tool: tool, canReviewWrites: item.canReviewWrites)
                        Divider().overlay(palette.border)
                    }
                } else {
                    Text(VyronPluginText.noTools)
                        .font(VyronPluginsStyle.body).foregroundStyle(palette.muted)
                }
            }
            if item.isPenpot {
                VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
                    Text(VyronPluginText.penpotHelp).font(VyronPluginsStyle.body).foregroundStyle(palette.muted)
                    if let url = VyronPluginItem.documentationURL {
                        Link(VyronPluginText.penpotDocs, destination: url)
                            .font(VyronPluginsStyle.action).foregroundStyle(palette.accent)
                    }
                }
            }
        }
    }
}
