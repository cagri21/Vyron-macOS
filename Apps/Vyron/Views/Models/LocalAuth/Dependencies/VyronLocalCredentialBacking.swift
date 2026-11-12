import Foundation
import VyronCore

protocol VyronLocalCredentialBacking: Sendable {
    func synchronize(connectionIDs: [UUID]) async throws -> VyronLocalCredentialBackupResult
    func remove(connectionID: UUID) async throws -> VyronLocalAuthStatus
}

extension VyronLocalCredentialBackup: VyronLocalCredentialBacking {}
