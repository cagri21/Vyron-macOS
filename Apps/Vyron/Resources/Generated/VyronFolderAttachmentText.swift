// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronFolderAttachmentText {
    static var analysisPrompt: String {
        VyronResourceBundle.string("folderAttachmentAnalysisPrompt", fallback: "Analyze the attached folders. Summarize their structure and the supplied file contents, identify issues, and suggest improvements. Clearly state any coverage limits.")
    }
    static var chooseFolder: String {
        VyronResourceBundle.string("folderAttachmentChooseFolder", fallback: "Attach a folder…")
    }
    static var contextTooLarge: String {
        VyronResourceBundle.string("folderAttachmentContextTooLarge", fallback: "The attached folders and message exceed the analysis limit. Remove a folder or shorten your message.")
    }
    static var importing: String {
        VyronResourceBundle.string("folderAttachmentImporting", fallback: "Preparing attachments…")
    }
    static var invalidFolder: String {
        VyronResourceBundle.string("folderAttachmentInvalidFolder", fallback: "Drop a readable folder. Symbolic links are not supported.")
    }
    static var limited: String {
        VyronResourceBundle.string("folderAttachmentLimited", fallback: "Some contents were omitted to fit the analysis limit.")
    }
    static func privacyHint(_ p1: String) -> String {
        VyronResourceBundle.format(
            "folderAttachmentPrivacyHint",
            fallback: "Folder names and readable text are sent to %@ when you send your message.",
            arguments: [p1]
        )
    }
    static func readFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "folderAttachmentReadFailed",
            fallback: "Could not read the folder. %@",
            arguments: [p1]
        )
    }
    static var ready: String {
        VyronResourceBundle.string("folderAttachmentReady", fallback: "Folder ready to analyze")
    }
    static func remove(_ p1: String) -> String {
        VyronResourceBundle.format(
            "folderAttachmentRemove",
            fallback: "Remove %@",
            arguments: [p1]
        )
    }
    static func summary(_ p1: Int, _ p2: Int) -> String {
        VyronResourceBundle.format(
            "folderAttachmentSummary",
            fallback: "%d files included · %d skipped",
            arguments: [p1, p2]
        )
    }
    static var tooMany: String {
        VyronResourceBundle.string("folderAttachmentTooMany", fallback: "Attach up to four folders at a time.")
    }
}
