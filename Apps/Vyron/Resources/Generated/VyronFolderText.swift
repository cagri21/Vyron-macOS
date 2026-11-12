// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronFolderText {
    static var allow: String {
        VyronResourceBundle.string("folderAllow", fallback: "Allow")
    }
    static var createOutsideProjectReason: String {
        VyronResourceBundle.string("folderCreateOutsideProjectReason", fallback: "Create a folder at the requested destination outside the current project.")
    }
    static var creating: String {
        VyronResourceBundle.string("folderCreating", fallback: "Creating folder")
    }
    static var ready: String {
        VyronResourceBundle.string("folderReady", fallback: "Folder is ready")
    }
    static func reviewDetails(_ p1: String) -> String {
        VyronResourceBundle.format(
            "folderReviewDetails",
            fallback: "Allow Vyron to create this folder and use it as a project if requested?\n\n%@\n\nExisting files will be preserved.",
            arguments: [p1]
        )
    }
    static var reviewTitle: String {
        VyronResourceBundle.string("folderReviewTitle", fallback: "Allow folder access?")
    }
    static var saveFailed: String {
        VyronResourceBundle.string("folderSaveFailed", fallback: "Could not save the new project selection. The current project is unchanged.")
    }
}
