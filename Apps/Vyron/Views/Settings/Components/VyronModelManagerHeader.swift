import SwiftUI

struct VyronModelManagerHeader: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var localizationLocale

    var body: some View {
        let _ = localizationLocale
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: VyronSettingsStyle.textSpacing) {
                Text(VyronSettingsText.models).font(VyronSettingsStyle.title)
                Text(VyronSettingsText.modelsDescription)
                    .font(VyronSettingsStyle.detail).foregroundStyle(palette.muted)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: VyronSymbols.close).font(VyronSettingsStyle.sidebarIcon)
            }
            .buttonStyle(QuietButtonStyle())
            .help(VyronAppText.settingsCloseModels)
            .accessibilityLabel(VyronAppText.settingsCloseModels)
        }
        .padding(VyronSettingsStyle.modelManagerInset)
    }
}
