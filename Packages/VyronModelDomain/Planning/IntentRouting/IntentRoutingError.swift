import Foundation
import VyronLocalization

public enum IntentRoutingError: Error, LocalizedError, Sendable, Equatable {
    case invalidText
    case invalidRoute

    public var errorDescription: String? {
        switch self {
        case .invalidText:
            let language = VyronResourceLanguage.selection
            let locale = Locale(identifier: language.resolved().rawValue)
            let maximumKilobytes = VyronTaskPromptLimits.maximumUTF8Bytes / 1_000
            return VyronModelDomainText.routingInvalidText(
                maximumKilobytes.formatted(.number.locale(locale)),
                language: language
            )
        case .invalidRoute:
            return VyronModelDomainText.routingInvalidRoute
        }
    }
}
