import SwiftUI
import VyronCore

struct VyronBuiltinModelSettingsSection: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var draft = VyronModelSettingsDraft(ModelSettings())
    @State private var error: String?
    @State private var expanded = false

    var body: some View {
        let _ = localizationLocale
        DisclosureGroup(VyronAppText.settingsLocalModelSettings, isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 13) {
                VyronModelSettingsFields(
                    draft: $draft,
                    thinkingSupport: model.modelThinkingSupport
                )
                if let error { Text(error).font(.system(size: 10)).foregroundStyle(palette.warning) }
                HStack {
                    Button(VyronAppText.settingsUseDefaults) {
                        draft = VyronModelSettingsDraft(ModelSettings()); save()
                    }
                    .buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button(VyronAppText.settingsApply) { save() }.buttonStyle(AccentButtonStyle())
                }.disabled(
                    !model.canManageModelSelection || model.modelDownloads.isActive
                        || model.modelSelection.connectionOperationInProgress
                )
            }.padding(.top, 13)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(16).background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .onAppear { loadDraft(model.modelSelection.builtinModelSettings) }
        .onChange(of: model.modelSelection.builtinModelSettings) { _, value in loadDraft(value) }
    }

    private func loadDraft(_ settings: ModelSettings) {
        var value = VyronModelSettingsDraft(settings)
        value.reconcileThinking(with: model.modelThinkingSupport)
        draft = value
    }

    private func save() {
        do {
            let settings = try draft.settings(thinkingSupport: model.modelThinkingSupport)
            try model.saveBuiltinModelSettings(settings)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
