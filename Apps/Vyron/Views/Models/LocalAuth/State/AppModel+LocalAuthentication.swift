import Foundation
import VyronCore

extension AppModel {
    func requestLocalCredentialSynchronization() {
        guard !isShuttingDown else { return }
        let ids = modelSelection.connectionProfiles.map(\.id)
        let context = VyronLocalCredentialRestoreContext(
            activeConnectionID: modelSelection.activeConnectionID,
            connectionRevision: modelSelection.connectionRevision,
            mutations: localAuthentication.mutationSnapshot(connectionIDs: ids)
        )
        localAuthentication.synchronize(
            connectionIDs: ids,
            actions: VyronLocalCredentialRestoreActions(
                restore: { [weak self] candidate in
                    guard let self else { return false }
                    return try self.restoreLocalCredential(candidate, context: context)
                },
                didRestore: { [weak self] restored in
                    await self?.refreshRestoredConnection(restored, context: context)
                }
            )
        )
    }

    private func restoreLocalCredential(
        _ candidate: VyronLocalCredentialRestoration,
        context: VyronLocalCredentialRestoreContext
    ) throws -> Bool {
        guard !isShuttingDown, !Task.isCancelled,
            modelSelection.connectionProfiles.contains(where: { $0.id == candidate.connectionID }),
            localAuthentication.matchesMutation(
                connectionID: candidate.connectionID,
                token: context.mutations[candidate.connectionID]
            )
        else { return false }
        let restored: Bool
        do {
            guard try modelCredentialStore.key(for: candidate.connectionID).isEmpty else { return false }
            restored = try modelCredentialStore.restoreKeyIfMissing(candidate.key, for: candidate.connectionID)
        } catch { throw VyronLocalAuthError.credentialsUnavailable }
        if restored { connectionBalances.credentialChanged(candidate.connectionID) }
        return restored
    }

    private func refreshRestoredConnection(
        _ restored: [UUID],
        context: VyronLocalCredentialRestoreContext
    ) async {
        guard !isShuttingDown, !Task.isCancelled,
            let id = context.activeConnectionID, restored.contains(id),
            modelSelection.activeConnectionID == id, modelSelection.connectionRevision == context.connectionRevision,
            canManageModelSelection, !modelSelection.connectionOperationInProgress, !modelDownloads.isActive,
            !newSideChatSessions.values.contains(where: \.isGenerating)
        else { return }
        await activateConnection(id)
    }
}
