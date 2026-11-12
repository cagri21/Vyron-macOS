import Foundation
import VyronLocalization

extension VyronTaskPromptLimits {
    static func formattedMaximumCharacters(language: VyronResourceLanguage) -> String {
        maximumCharacters.formatted(.number.locale(Locale(identifier: language.resolved().rawValue)))
    }
}
