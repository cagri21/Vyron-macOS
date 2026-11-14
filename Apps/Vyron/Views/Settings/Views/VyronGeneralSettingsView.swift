import SwiftUI

struct VyronGeneralSettingsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var localization: VyronLocalization

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSettingsStyle.sectionSpacing) {
            VStack(alignment: .leading, spacing: VyronSettingsStyle.headingSpacing) {
                Text(VyronSettingsText.general)
                    .font(VyronSettingsStyle.sectionTitle)
                VyronSettingsCard {
                    VyronSettingsRow(VyronLanguageText.title, detail: VyronSettingsText.languageDescription) {
                        Picker(VyronLanguageText.title, selection: $localization.language) {
                            ForEach(VyronLanguage.allCases) { language in
                                Text(verbatim: language.nativeName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: VyronSettingsStyle.controlWidth)
                    }
                    Divider().overlay(palette.border)
                    VyronSettingsRow(VyronQueueText.messages, detail: VyronSettingsText.queueDescription) {
                        Toggle(VyronQueueText.messages, isOn: Binding(
                            get: { model.composer.queueMessages },
                            set: { model.composer.queueMessages = $0 }
                        ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Divider().overlay(palette.border)
                    permissionsLink
                }
            }
            VStack(alignment: .leading, spacing: VyronSettingsStyle.headingSpacing) {
                Text(VyronSettingsText.workspace)
                    .font(VyronSettingsStyle.sectionTitle)
                VyronSettingsCard {
                    VyronSettingsRow(VyronSettingsText.inspector, detail: VyronSettingsText.inspectorDescription) {
                        Toggle(VyronSettingsText.inspector, isOn: Binding(
                            get: { model.appNavigation.showWorkspace }, set: { model.appNavigation.showWorkspace = $0 }
                        ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    Divider().overlay(palette.border)
                    VyronSettingsRow(VyronSettingsText.terminal, detail: VyronSettingsText.terminalDescription) {
                        Toggle(
                            VyronSettingsText.terminal,
                            isOn: Binding(
                                get: { model.inspector.showTerminal },
                                set: { model.inspector.showTerminal = $0 }
                            )
                        )
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }
        }
        .foregroundStyle(palette.text)
    }

    private var permissionsLink: some View {
        Button {
            model.appNavigation.settingsSection = .permissions
        } label: {
            VyronSettingsRow(VyronPermissionsText.title, detail: VyronPermissionsText.generalDescription) {
                Image(systemName: VyronSymbols.chevronRight)
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VyronPermissionsText.title)
        .accessibilityHint(VyronPermissionsText.generalDescription)
    }
}
