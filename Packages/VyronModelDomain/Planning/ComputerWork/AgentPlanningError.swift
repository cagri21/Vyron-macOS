import Foundation
import VyronLocalization

public enum AgentPlanningError: Error, LocalizedError, Sendable, Equatable {
    case invalidGoal
    case noApplications
    case noEligibleModel
    case inputTooLarge
    case invalidDecision(String)

    public var errorDescription: String? {
        let language = VyronResourceLanguage.selection
        return switch self {
        case .invalidGoal:
            VyronModelDomainText.agentInvalidGoal(
                VyronTaskPromptLimits.formattedMaximumCharacters(language: language),
                language: language
            )
        case .noApplications: VyronModelDomainText.agentNoApplications
        case .noEligibleModel: VyronModelDomainText.agentNoEligibleModel
        case .inputTooLarge: VyronModelDomainText.agentInputTooLarge
        case .invalidDecision(let detail): VyronModelDomainText.agentInvalidDecision(detail)
        }
    }
}
