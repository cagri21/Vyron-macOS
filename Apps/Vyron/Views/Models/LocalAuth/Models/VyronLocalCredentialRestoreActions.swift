import Foundation
import VyronCore

struct VyronLocalCredentialRestoreActions {
    let restore: @MainActor (VyronLocalCredentialRestoration) throws -> Bool
    let didRestore: @MainActor ([UUID]) async -> Void
}
