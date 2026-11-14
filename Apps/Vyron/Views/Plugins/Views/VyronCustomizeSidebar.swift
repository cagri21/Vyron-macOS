import SwiftUI

struct VyronCustomizeSidebar: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @ObservedObject var connections: MCPConnectionsModel
    @ObservedObject var presentation: VyronPluginsPresentation

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronPluginsStyle.sectionSpacing) {
            Text(VyronPluginText.customize)
                .font(VyronPluginsStyle.sidebarTitle)
                .padding(.horizontal, VyronPluginsStyle.compactSpacing)

            VStack(spacing: VyronPluginsStyle.compactSpacing) {
                sectionButton(
                    VyronPluginText.title,
                    symbol: VyronSymbols.plugins,
                    section: .plugins
                ) { presentation.showAll() }
                sectionButton(
                    VyronSkillText.title,
                    symbol: VyronSymbols.skills,
                    section: .skills
                ) { presentation.showSkills() }
            }

            VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
                Text(VyronPluginText.installed)
                    .font(VyronPluginsStyle.caption)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, VyronPluginsStyle.compactSpacing)

                ScrollView {
                    VStack(alignment: .leading, spacing: VyronPluginsStyle.compactSpacing) {
                        ForEach(connections.profiles) { profile in
                            Button {
                                presentation.select(profile.id)
                            } label: {
                                HStack(spacing: VyronPluginsStyle.rowSpacing) {
                                    VyronPluginAvatar(isPenpot: VyronPluginItem(profile: profile).isPenpot, compact: true)
                                    Text(verbatim: profile.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if connections.isConnected(profile.id) {
                                        Circle().fill(palette.success)
                                            .frame(
                                                width: VyronPluginsStyle.statusSize,
                                                height: VyronPluginsStyle.statusSize
                                            )
                                    }
                                }
                                .font(VyronPluginsStyle.body)
                                .padding(VyronPluginsStyle.compactSpacing)
                                .background(
                                    presentation.section == .plugins && presentation.selectedConnectionID == profile.id
                                        ? palette.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: VyronPluginsStyle.rowRadius)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                model.returnToWorkspace()
            } label: {
                Label(VyronPluginText.returnToWorkspace, systemImage: VyronSymbols.back)
                    .font(VyronPluginsStyle.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.muted)
        }
        .padding(.horizontal, VyronPluginsStyle.sidebarPadding)
        .padding(.top, VyronPluginsStyle.headerTopPadding)
        .padding(.bottom, VyronPluginsStyle.sidebarPadding)
        .background(palette.sidebar)
    }

    private func sectionButton(
        _ title: String,
        symbol: String,
        section: VyronCustomizeSection,
        action: @escaping () -> Void
    ) -> some View {
        let selected = presentation.section == section
        return Button(action: action) {
            Label(title, systemImage: symbol)
                .font(VyronPluginsStyle.body)
                .foregroundStyle(selected ? palette.text : palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(VyronPluginsStyle.rowSpacing)
                .background(
                    selected ? palette.selection : .clear,
                    in: RoundedRectangle(cornerRadius: VyronPluginsStyle.rowRadius)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
