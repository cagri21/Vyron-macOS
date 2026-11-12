import Foundation
import VyronLocalization

public enum ControlPlanningError: Error, LocalizedError, Sendable, Equatable {
    case invalidInstruction
    case invalidProposal(String)

    public var errorDescription: String? {
        let language = VyronResourceLanguage.selection
        switch self {
        case .invalidInstruction:
            return VyronModelDomainText.controlInvalidInstruction(
                VyronTaskPromptLimits.formattedMaximumCharacters(language: language),
                language: language
            )
        case .invalidProposal(let reason):
            let detail = VyronControlProposalRejection.localizedDetail(reason, language: language)
            return VyronModelDomainText.controlInvalidProposal(detail, language: language)
        }
    }

    package var modelFeedback: String {
        switch self {
        case .invalidInstruction:
            VyronModelDomainText.controlInvalidInstruction(
                VyronTaskPromptLimits.formattedMaximumCharacters(language: .english),
                language: .english
            )
        case .invalidProposal(let reason):
            VyronModelDomainText.controlInvalidProposal(reason, language: .english)
        }
    }
}
