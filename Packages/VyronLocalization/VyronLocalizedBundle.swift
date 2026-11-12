import Foundation

package struct VyronLocalizedBundle: Sendable {
    private let bundle: Bundle

    package init(_ bundle: Bundle) {
        self.bundle = bundle
    }

    package func localized(
        for language: VyronResourceLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bundle {
        let resolved = language.resolved(preferredLanguages: preferredLanguages)
        return bundle(for: resolved) ?? bundle(for: .english) ?? bundle
    }

    package func string(_ key: String, fallback: String, language: VyronResourceLanguage? = nil) -> String {
        let value = localized(for: language ?? .selection).localizedString(forKey: key, value: nil, table: nil)
        if value != key { return value }
        let english = localized(for: .english).localizedString(forKey: key, value: nil, table: nil)
        return english == key ? fallback : english
    }

    package func format(
        _ key: String,
        fallback: String,
        arguments: [CVarArg],
        language: VyronResourceLanguage? = nil
    ) -> String {
        let selection = language ?? .selection
        return String(
            format: string(key, fallback: fallback, language: selection),
            locale: Locale(identifier: selection.resolved().rawValue),
            arguments: arguments
        )
    }

    private func bundle(for language: VyronResourceLanguage) -> Bundle? {
        guard let path = bundle.path(forResource: language.rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}
