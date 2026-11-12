import Foundation
import VyronLocalization

/// No server body, URL, transport description, or credential is exposed in these errors.
public enum VyronConnectionBalanceError: Error, LocalizedError, Equatable, Sendable {
    case unsupported
    case missingKey
    case authenticationFailed
    case rateLimited
    case temporarilyUnavailable
    case noKeyLimit
    case invalidResponse
    case connectionFailed

    public var errorDescription: String? {
        switch self {
        case .unsupported: VyronModelDomainText.balanceUnsupported
        case .missingKey: VyronModelDomainText.balanceMissingKey
        case .authenticationFailed: VyronModelDomainText.balanceAuthenticationFailed
        case .rateLimited: VyronModelDomainText.balanceRateLimited
        case .temporarilyUnavailable: VyronModelDomainText.balanceTemporarilyUnavailable
        case .noKeyLimit: VyronModelDomainText.balanceNoKeyLimit
        case .invalidResponse: VyronModelDomainText.balanceInvalidResponse
        case .connectionFailed: VyronModelDomainText.balanceConnectionFailed
        }
    }
}
