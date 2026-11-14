import SwiftUI

struct VyronIntegrationSettingsView: View {
    @Environment(\.vyronPalette) private var palette
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
                Divider().overlay(palette.border)
                HStack {
                    Text(VyronSettingsText.savedConnections)
                    Spacer()
                    Text(connections.profiles.count, format: .number)
                        .foregroundStyle(palette.muted)
                }
                .font(VyronSettingsStyle.body)
                .padding(.vertical, VyronSettingsStyle.rowPadding)
            }
            Text(VyronPluginText.securityNote)
                .font(VyronSettingsStyle.detail)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(palette.text)
    }
}
