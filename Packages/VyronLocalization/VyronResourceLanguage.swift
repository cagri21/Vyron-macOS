import Foundation

package enum VyronResourceLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case turkish = "tr"
    case ukrainian = "uk"

    package static var selection: Self {
        UserDefaults.standard.string(forKey: VyronLocalizationDefaultsKey.language.rawValue)
            .flatMap(Self.init(rawValue:)) ?? .system
    }

    package var id: String { rawValue }

    package func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        guard self == .system else { return self }
        for identifier in preferredLanguages {
            let code = identifier.replacingOccurrences(of: "_", with: "-")
                .lowercased().split(separator: "-").first.map(String.init)
            if let code, let language = Self(rawValue: code), language != .system {
                return language
            }
        }
        return .english
    }
}
