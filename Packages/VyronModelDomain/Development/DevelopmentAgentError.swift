import Foundation
import VyronLocalization

public enum DevelopmentAgentError: Error, LocalizedError, Sendable, Equatable {
    case invalidGoal
    case noCodingModel
    case unsupportedModel(String)
    case alreadyRunning
    case invalidTool(String)
    case contextBudget

    public var errorDescription: String? {
        switch self {
        case .invalidGoal:
            VyronModelDomainText.developmentInvalidGoal
        case .noCodingModel:
            VyronModelDomainText.developmentNoCodingModel
        case .unsupportedModel(let reason): VyronModelDomainText.developmentUnsupportedModel(reason)
        case .alreadyRunning: VyronModelDomainText.developmentAlreadyRunning
        case .invalidTool(let reason): VyronModelDomainText.developmentInvalidTool(reason)
        case .contextBudget: VyronModelDomainText.contextBudget
        }
    }
}
