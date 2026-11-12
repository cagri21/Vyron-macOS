import SwiftUI

struct VyronIntegrationSettingsView: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @ObservedObject var connections: MCPConnectionsModel

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSettingsStyle.sectionSpacing) {
            VyronSettingsCard {
                VyronAutomaticSkillSetupSetting()
            }
            VyronSettingsCard {
                VyronOfficeSettingsView()
            }
            VyronSettingsCard {
                VyronSettingsRow(VyronSettingsText.connectedTools, detail: VyronPluginText.subtitle) {
                    Button(VyronSettingsText.managePlugins) {
                        openWindow(id: VyronAppWindow.main)
                        model.openPlugins()
                    }
                    .buttonStyle(.bordered)
                }
                Divider().overlay(Palette.border)
                HStack {
                    Text(VyronSettingsText.savedConnections)
                    Spacer()
                    Text(connections.profiles.count, format: .number)
                        .foregroundStyle(Palette.muted)
                }
                .font(VyronSettingsStyle.body)
                .padding(.vertical, VyronSettingsStyle.rowPadding)
            }
            Text(VyronPluginText.securityNote)
                .font(VyronSettingsStyle.detail)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.text)
    }
}
