import Foundation
import VyronModelDomain

/// Only validated, exhausted content failures can enter the agent's bounded recovery.
package struct VyronDevelopmentReplyFailure: Error, LocalizedError, Sendable {
    package let originalError: LocalAIError
    package let diagnostic: VyronOllamaReplyDiagnostic

    package var errorDescription: String? { originalError.errorDescription }
}
