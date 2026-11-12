import SwiftUI

struct VyronAutomaticSkillSetupSetting: View {
    @AppStorage(VyronUserDefaultsKey.automaticallySetUpSkills.rawValue)
    private var isEnabled = VyronSkillSetupPreferences.defaultValue

    var body: some View {
        VyronSettingsRow(VyronSkillText.automaticSetupTitle, detail: VyronSkillText.automaticSetupDescription) {
            Toggle(VyronSkillText.automaticSetupTitle, isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
