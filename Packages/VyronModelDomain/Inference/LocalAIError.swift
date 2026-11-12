import Foundation
import VyronLocalization

public enum LocalAIError: Error, LocalizedError, Sendable, Equatable {
    case invalidEndpoint
    case invalidModelName
    case cloudModelNotAllowed
    case modelNotInstalled(String)
    case connectionFailed
    case httpError(Int, String)
    case invalidResponse(String)
    case incompleteStream
    case workspace(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return VyronModelDomainText.ollamaInvalidEndpoint
        case .invalidModelName:
            return VyronModelDomainText.ollamaInvalidModelName
        case .cloudModelNotAllowed:
            return VyronModelDomainText.ollamaCloudModelNotAllowed
        case .modelNotInstalled(let name):
            return VyronModelDomainText.ollamaModelNotInstalled(name)
        case .connectionFailed:
            return VyronModelDomainText.ollamaConnectionFailed
        case .httpError(let status, let detail):
            return detail.isEmpty
                ? VyronModelDomainText.ollamaHTTPError(String(status))
                : VyronModelDomainText.ollamaHTTPDetail(detail)
        case .invalidResponse(let detail):
            return VyronModelDomainText.ollamaInvalidResponse(detail)
        case .incompleteStream:
            return VyronModelDomainText.ollamaIncompleteStream
        case .workspace(let detail):
            return detail
        }
    }
}
