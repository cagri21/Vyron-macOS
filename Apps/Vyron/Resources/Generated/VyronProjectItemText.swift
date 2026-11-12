// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronProjectItemText {
    static var moveAllow: String {
        VyronResourceBundle.string("projectItemMoveAllow", fallback: "Move")
    }
    static var moved: String {
        VyronResourceBundle.string("projectItemMoved", fallback: "Item moved")
    }
    static func moveReviewDetails(_ p1: String) -> String {
        VyronResourceBundle.format(
            "projectItemMoveReviewDetails",
            fallback: "Allow Vyron to move this project file or folder?\n\n%@\n\nExisting destination items will not be replaced.",
            arguments: [p1]
        )
    }
    static var moveReviewTitle: String {
        VyronResourceBundle.string("projectItemMoveReviewTitle", fallback: "Move this item?")
    }
    static var moving: String {
        VyronResourceBundle.string("projectItemMoving", fallback: "Moving item")
    }
    static var renameAllow: String {
        VyronResourceBundle.string("projectItemRenameAllow", fallback: "Rename")
    }
    static var renamed: String {
        VyronResourceBundle.string("projectItemRenamed", fallback: "Item renamed")
    }
    static func renameReviewDetails(_ p1: String) -> String {
        VyronResourceBundle.format(
            "projectItemRenameReviewDetails",
            fallback: "Allow Vyron to rename this project file or folder?\n\n%@\n\nExisting destination items will not be replaced.",
            arguments: [p1]
        )
    }
    static var renameReviewTitle: String {
        VyronResourceBundle.string("projectItemRenameReviewTitle", fallback: "Rename this item?")
    }
    static var renaming: String {
        VyronResourceBundle.string("projectItemRenaming", fallback: "Renaming item")
    }
    static var trashAllow: String {
        VyronResourceBundle.string("projectItemTrashAllow", fallback: "Move to Trash")
    }
    static var trashed: String {
        VyronResourceBundle.string("projectItemTrashed", fallback: "Item moved to Trash")
    }
    static var trashing: String {
        VyronResourceBundle.string("projectItemTrashing", fallback: "Moving item to Trash")
    }
    static func trashReviewDetails(_ p1: String) -> String {
        VyronResourceBundle.format(
            "projectItemTrashReviewDetails",
            fallback: "Allow Vyron to move this project file or folder to the Mac’s Trash?\n\n%@\n\nYou can restore it from Trash.",
            arguments: [p1]
        )
    }
    static var trashReviewTitle: String {
        VyronResourceBundle.string("projectItemTrashReviewTitle", fallback: "Move this item to Trash?")
    }
}
