import Foundation
import VyronLocalization

enum ModelCredentialError: Error, LocalizedError {
    case unavailable
    var errorDescription: String? {
        VyronModelDataText.credentialUnavailable
    }
}
