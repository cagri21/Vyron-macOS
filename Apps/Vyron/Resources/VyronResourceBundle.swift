import Foundation
import VyronLocalization

enum VyronResourceBundle {
    static let current: Bundle = {
        // The app packaging script puts SwiftPM's resources in the native Resources folder.
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Vyron_Vyron.bundle"),
            let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    private static let strings = VyronLocalizedBundle(current)

    static var localized: Bundle {
        localized(for: .selection)
    }

    static var locale: Locale {
        Locale(identifier: VyronLanguage.selection.resolved().rawValue)
    }

    static func localized(
        for language: VyronLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bundle {
        strings.localized(for: language, preferredLanguages: preferredLanguages)
    }

    static func string(_ key: String, fallback: String, language: VyronLanguage? = nil) -> String {
        strings.string(key, fallback: fallback, language: language)
    }

    static func format(
        _ key: String,
        fallback: String,
        arguments: [CVarArg],
        language: VyronLanguage? = nil
    ) -> String {
        strings.format(key, fallback: fallback, arguments: arguments, language: language)
    }
}
