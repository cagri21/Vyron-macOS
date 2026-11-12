import Foundation

enum VyronSkillSetupPreferences {
    static let defaultValue = true

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: VyronUserDefaultsKey.automaticallySetUpSkills.rawValue) as? Bool
            ?? defaultValue
    }
}
