// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronFolderAttachmentText {
    static func pdfPreview(_ p1: String) -> String {
        VyronResourceBundle.format(
            "folderAttachmentPdfPreview",
            fallback: "Preview first page of %@",
            arguments: [p1]
        )
    }
    static func pdfPrivacyHint(_ p1: String) -> String {
        VyronResourceBundle.format(
            "folderAttachmentPdfPrivacyHint",
            fallback: "When you send, %@ receives text extracted locally from the PDF. The preview and text are saved in this chat’s history.",
            arguments: [p1]
        )
    }
    static var pdfReady: String {
        VyronResourceBundle.string("folderAttachmentPdfReady", fallback: "PDF ready to analyze")
    }
    static func pdfTooLarge(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "folderAttachmentPdfTooLarge",
            fallback: "This PDF exceeds the %d MiB import limit.",
            arguments: [p1]
        )
    }
    static func pdfTooMany(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "folderAttachmentPdfTooMany",
            fallback: "Attach up to %d PDFs at a time.",
            arguments: [p1]
        )
    }
    static var pdfUnreadable: String {
        VyronResourceBundle.string("folderAttachmentPdfUnreadable", fallback: "Choose a readable PDF with text copying allowed.")
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
