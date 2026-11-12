import VyronLocalization

typealias VyronLanguage = VyronResourceLanguage

extension VyronLanguage {
    var nativeName: String {
        switch self {
        case .system: VyronLanguageText.system
        case .english: "English"
        case .turkish: "Türkçe"
        case .ukrainian: "Українська"
        }
    }
}
