import Combine
import Foundation
import VyronLocalization

@MainActor
final class VyronLocalization: ObservableObject {
    @Published var language: VyronLanguage {
        didSet {
            if language == .system {
                defaults.removeObject(forKey: VyronLocalizationDefaultsKey.language.rawValue)
            } else {
                defaults.set(language.rawValue, forKey: VyronLocalizationDefaultsKey.language.rawValue)
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: VyronLocalizationDefaultsKey.language.rawValue)
            .flatMap(VyronLanguage.init(rawValue:)) ?? .system
    }

    var locale: Locale {
        Locale(identifier: language.resolved().rawValue)
    }
}
