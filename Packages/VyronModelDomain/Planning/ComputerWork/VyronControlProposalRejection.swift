import Foundation
import VyronLocalization

enum VyronControlProposalRejection: CaseIterable, Sendable {
    case unsupportedFields
    case applicationRequired
    case unexpectedApplication
    case explanationRequired
    case elementOutsideSnapshot
    case elementMissingFromSnapshot
    case applicationOnly
    case invalidWait
    case invalidWebURL
    case elementRequired
    case invalidTypedText
    case unsupportedNavigationKey
    case browserRequired

    private static let byEnglishDetail = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.detail(language: .english), $0) }
    )

    var error: ControlPlanningError {
        .invalidProposal(detail(language: .english))
    }

    // Public callers can supply their own details. Only these owned reasons have translations.
    static func localizedDetail(_ detail: String, language: VyronResourceLanguage) -> String {
        byEnglishDetail[detail]?.detail(language: language) ?? detail
    }

    private func detail(language: VyronResourceLanguage) -> String {
        switch self {
        case .unsupportedFields:
            return VyronModelDomainText.controlRejectUnsupportedFields(language: language)
        case .applicationRequired:
            return VyronModelDomainText.controlRejectApplicationRequired(language: language)
        case .unexpectedApplication:
            return VyronModelDomainText.controlRejectUnexpectedApplication(language: language)
        case .explanationRequired:
            return VyronModelDomainText.controlRejectExplanationRequired(language: language)
        case .elementOutsideSnapshot:
            return VyronModelDomainText.controlRejectElementOutsideSnapshot(language: language)
        case .elementMissingFromSnapshot:
            return VyronModelDomainText.controlRejectElementMissingFromSnapshot(language: language)
        case .applicationOnly:
            return VyronModelDomainText.controlRejectApplicationOnly(language: language)
        case .invalidWait:
            let range = VyronControlProposalLimits.waitSeconds
            let locale = Locale(identifier: language.resolved().rawValue)
            return VyronModelDomainText.controlRejectInvalidWait(
                range.lowerBound.formatted(.number.locale(locale)),
                range.upperBound.formatted(.number.locale(locale)),
                language: language
            )
        case .invalidWebURL:
            return VyronModelDomainText.controlRejectInvalidWebURL(language: language)
        case .elementRequired:
            return VyronModelDomainText.controlRejectElementRequired(language: language)
        case .invalidTypedText:
            return VyronModelDomainText.controlRejectInvalidTypedText(language: language)
        case .unsupportedNavigationKey:
            return VyronModelDomainText.controlRejectUnsupportedNavigationKey(language: language)
        case .browserRequired:
            return VyronModelDomainText.controlRejectBrowserRequired(language: language)
        }
    }
}
