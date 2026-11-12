import Foundation
import VyronModelDomain

struct VyronBuiltinModelPreferences {
    let defaults: UserDefaults

    var model: String {
        get {
            defaults.string(forKey: VyronUserDefaultsKey.selectedLocalModel.rawValue)
                ?? ModelCatalog.recommendedCodingTag
        }
        nonmutating set { defaults.set(newValue, forKey: VyronUserDefaultsKey.selectedLocalModel.rawValue) }
    }

    var automaticallySelect: Bool {
        get { defaults.object(forKey: VyronUserDefaultsKey.automaticModelSelection.rawValue) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: VyronUserDefaultsKey.automaticModelSelection.rawValue) }
    }
}
