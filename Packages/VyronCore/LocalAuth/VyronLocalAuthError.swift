import Foundation

public enum VyronLocalAuthError: Error, Sendable, Equatable, LocalizedError {
    case invalidConfiguration
    case credentialsUnavailable
    case encryptionKeyMissing
    case unauthorized
    case invalidResponse
    case unavailable
    case conflict
    case integrityFailed

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "The local credential service configuration is unavailable or unsafe."
        case .credentialsUnavailable: "The local credential service could not access its device credentials."
        case .encryptionKeyMissing: "The encryption key for the existing credential backup is missing."
        case .unauthorized: "The local credential service rejected this device."
        case .invalidResponse: "The local credential service returned an invalid response."
        case .unavailable: "The local credential service is unavailable."
        case .conflict: "The credential backup changed. Retry synchronization."
        case .integrityFailed: "The encrypted credential backup could not be verified."
        }
    }
}
