import Foundation
import VyronDevelopment

extension AppModel {
    func recordResponseChanges(_ snapshots: [VyronDevelopmentResponseChanges], response: VyronResponseIdentity) {
        guard !snapshots.isEmpty,
            let index = conversations.firstIndex(where: { $0.id == response.conversationID }),
            conversations[index].messages.contains(where: { $0.id == response.messageID })
        else { return }
        var byResponse = conversations[index].changesByResponseID ?? [:]
        byResponse[response.messageID.uuidString] = snapshots
        conversations[index].changesByResponseID = byResponse
        saveHistory()
    }

    func canUndoResponseChanges(_ snapshot: VyronDevelopmentResponseChanges) -> Bool {
        guard !isShuttingDown, foregroundRun.isIdle, foregroundRun.developmentResponse == nil,
            !isRunningScheduledTask, !computerWork.isComputerWorkActive,
            workspaceState.developmentWorkspace?.rootURL.path == snapshot.workspacePath,
            !snapshot.remainingChanges.isEmpty
        else { return false }
        let current = Dictionary(uniqueKeysWithValues: inspector.developmentChanges.map { ($0.path, $0) })
        return snapshot.remainingChanges.allSatisfy { change in
            guard let saved = current[change.path], saved.id == change.id else { return false }
            return saved.after.utf8.elementsEqual(change.after.utf8)
        }
    }

    func undoResponseChanges(conversationID: UUID, responseID: UUID, workspacePath: String) {
        Task {
            let key = responseID.uuidString
            guard selectedConversationID == conversationID,
                let snapshots = selectedConversation?.changesByResponseID?[key],
                let snapshot = snapshots.first(where: { $0.workspacePath == workspacePath }),
                canUndoResponseChanges(snapshot), let workspace = workspaceState.developmentWorkspace
            else { return }
            let url = workspaceState.workspaceURL
            do {
                let result = try await workspace.undoResponseChanges(snapshot.remainingChanges)
                if !result.restoredPaths.isEmpty,
                    let index = conversations.firstIndex(where: { $0.id == conversationID }),
                    var current = conversations[index].changesByResponseID?[key],
                    let scope = current.firstIndex(where: { $0.workspacePath == workspacePath }) {
                    current[scope].undonePaths = (current[scope].undonePaths ?? []).union(result.restoredPaths)
                    conversations[index].changesByResponseID?[key] = current
                    saveHistory()
                }
                await refreshDevelopmentState(project: workspace, expectedURL: url)
                if let error = result.errorMessage, selectedConversationID == conversationID { errorMessage = error }
            } catch {
                if selectedConversationID == conversationID { errorMessage = error.localizedDescription }
            }
        }
    }
}
