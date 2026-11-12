import Foundation
@testable import Vyron
import VyronCore

@MainActor
final class VyronLocalAuthenticationTestActions {
    var acceptsRestoration = true
    var restorationFailure: VyronLocalAuthError?
    private(set) var attempts: [VyronLocalCredentialRestoration] = []
    private(set) var refreshedConnections: [[UUID]] = []

    var actions: VyronLocalCredentialRestoreActions {
        VyronLocalCredentialRestoreActions(
            restore: { candidate in
                self.attempts.append(candidate)
                if let failure = self.restorationFailure { throw failure }
                return self.acceptsRestoration
            },
            didRestore: { ids in
                self.refreshedConnections.append(ids)
            }
        )
    }
}
