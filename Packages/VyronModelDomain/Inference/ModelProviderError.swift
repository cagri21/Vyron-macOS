import Foundation
import VyronLocalization

public enum ModelProviderError: Error, LocalizedError, Sendable, Equatable {
    case invalidEndpoint
    case invalidSettings(String)
    case invalidModel
    case connectionFailed
    case http(Int)
    case invalidResponse(String)
    case outputLimitReached
    case modelListUnavailable
    case unsupportedTools

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            VyronModelDomainText.providerInvalidEndpoint
        case .invalidSettings(let detail): detail
        case .invalidModel: VyronModelDomainText.providerInvalidModel
        case .connectionFailed: VyronModelDomainText.providerConnectionFailed
        case .http(let status):
            status == 401 || status == 403
                ? VyronModelDomainText.providerAccessRejected
                : VyronModelDomainText.providerHTTPError(String(status))
        case .invalidResponse(let detail): VyronModelDomainText.providerInvalidResponse(detail)
        case .outputLimitReached:
            VyronModelDomainText.providerOutputLimitReached
        case .modelListUnavailable: VyronModelDomainText.providerModelListUnavailable
        case .unsupportedTools:
            VyronModelDomainText.providerUnsupportedTools
        }
    }
}
