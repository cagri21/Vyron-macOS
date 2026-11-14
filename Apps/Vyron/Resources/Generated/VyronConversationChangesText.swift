// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronConversationChangesText {
    static func editedFiles(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "conversationChangesEditedFiles",
            fallback: "Edited %d files",
            arguments: [p1]
        )
    }
    static var undoChanges: String {
        VyronResourceBundle.string("conversationChangesUndoChanges", fallback: "Undo")
    }
    static var viewChanges: String {
        VyronResourceBundle.string("conversationChangesViewChanges", fallback: "View changes")
    }
}
