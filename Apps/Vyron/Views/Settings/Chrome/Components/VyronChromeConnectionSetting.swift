import SwiftUI
import VyronAutomation

struct VyronChromeConnectionSetting: View {
    @StateObject private var model: VyronChromeConnectionModel

    init(client: VyronChromeBridgeClient) {
        _model = StateObject(wrappedValue: VyronChromeConnectionModel(client: client))
    }

    var body: some View {
        VyronSettingsCard {
            VStack(alignment: .leading, spacing: VyronSettingsStyle.sectionSpacing) {
                Text(VyronChromeText.title).font(VyronSettingsStyle.body)
                Text(VyronChromeText.setup)
                    .font(VyronSettingsStyle.detail)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(VyronChromeText.extensionID, text: $model.extensionID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(VyronChromeText.extensionID)
                HStack {
                    Button(VyronChromeText.install) { model.install() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Text(VyronChromeText.sessions(model.sessionCount))
                        .font(VyronSettingsStyle.detail)
                        .foregroundStyle(Palette.muted)
                    Button(VyronChromeText.refresh) {
                        Task { await model.refresh() }
                    }
                    .disabled(model.isLoading)
                }
                Text(VyronChromeText.workHint)
                    .font(VyronSettingsStyle.detail)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = model.error ?? model.status {
                    Text(message)
                        .font(VyronSettingsStyle.detail)
                        .foregroundStyle(model.error == nil ? Palette.muted : Palette.warning)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, VyronSettingsStyle.rowPadding)
        }
        .task { await model.refresh() }
        .onDisappear { model.cancel() }
    }
}
