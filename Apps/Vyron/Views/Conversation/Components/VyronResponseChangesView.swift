import SwiftUI
import VyronDevelopment

struct VyronResponseChangesView: View {
    @EnvironmentObject private var model: AppModel
    let responseID: UUID

    var body: some View {
        if let conversation = model.selectedConversation,
            let snapshots = conversation.changesByResponseID?[responseID.uuidString] {
            ForEach(snapshots) { snapshot in
                VyronConversationChangesCard(
                    changes: snapshot.changes,
                    open: { change in
                        model.showChangeReview(
                            conversationID: conversation.id,
                            workspacePath: snapshot.workspacePath,
                            changes: snapshot.changes,
                            selectedPath: change.path
                        )
                    },
                    undo: model.canUndoResponseChanges(snapshot) ? {
                        model.undoResponseChanges(
                            conversationID: conversation.id, responseID: responseID, workspacePath: snapshot.workspacePath
                        )
                    } : nil
                )
            }
        }
    }
}
