import Foundation
import VyronCore

enum VyronOfficePreferences {
    static func configuration(defaults: UserDefaults = .standard) -> VyronOfficeConfiguration {
        VyronOfficeConfiguration(
            pythonExecutable: defaults.string(forKey: VyronUserDefaultsKey.officePythonExecutable.rawValue) ?? ""
        )
    }
}
