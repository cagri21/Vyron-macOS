import Foundation
@testable import Vyron
import VyronCore

/// Deliberately retains cancelled requests so tests can deliver stale responses later.
actor VyronLocalAuthenticationTestBackup: VyronLocalCredentialBacking {
    private(set) var synchronizations: [[UUID]] = []
    private(set) var removals: [UUID] = []
    private var synchronizationWaiters: [
        Int: CheckedContinuation<VyronLocalCredentialBackupResult, any Error>
    ] = [:]
    private var removalWaiters: [Int: CheckedContinuation<VyronLocalAuthStatus, any Error>] = [:]

    func synchronize(connectionIDs: [UUID]) async throws -> VyronLocalCredentialBackupResult {
        let index = synchronizations.count
        synchronizations.append(connectionIDs)
        return try await withCheckedThrowingContinuation { continuation in
            synchronizationWaiters[index] = continuation
        }
    }

    func remove(connectionID: UUID) async throws -> VyronLocalAuthStatus {
        let index = removals.count
        removals.append(connectionID)
        return try await withCheckedThrowingContinuation { continuation in
            removalWaiters[index] = continuation
        }
    }

    func finishSynchronization(
        _ index: Int,
        result: Result<VyronLocalCredentialBackupResult, any Error>
    ) -> Bool {
        guard let continuation = synchronizationWaiters.removeValue(forKey: index) else { return false }
        continuation.resume(with: result)
        return true
    }

    func finishRemoval(_ index: Int, result: Result<VyronLocalAuthStatus, any Error>) -> Bool {
        guard let continuation = removalWaiters.removeValue(forKey: index) else { return false }
        continuation.resume(with: result)
        return true
    }

    func cancelAll() {
        let synchronizations = synchronizationWaiters.values
        let removals = removalWaiters.values
        synchronizationWaiters.removeAll()
        removalWaiters.removeAll()
        for continuation in synchronizations { continuation.resume(throwing: CancellationError()) }
        for continuation in removals { continuation.resume(throwing: CancellationError()) }
    }
}
