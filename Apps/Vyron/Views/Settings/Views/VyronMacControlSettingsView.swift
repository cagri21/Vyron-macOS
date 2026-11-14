import SwiftUI

struct VyronMacControlSettingsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSettingsStyle.sectionSpacing) {
            VyronChromeConnectionSetting(client: model.chromeBridge)
                .disabled(model.isRunningScheduledTask)
            VyronSettingsCard {
                VyronSettingsRow(VyronSettingsText.macControls, detail: VyronSettingsText.macControlDescription) {
                    Button(VyronSettingsText.openControls) {
                        openWindow(id: VyronAppWindow.main)
                        model.appNavigation.showAutomation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isRunningScheduledTask)
                }
            }
            Text(VyronSettingsText.macControlHint)
                .font(VyronSettingsStyle.detail)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(palette.text)
    }
}
