// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronFolderAttachmentText {
    static var analysisPrompt: String {
        VyronResourceBundle.string("folderAttachmentAnalysisPrompt", fallback: "Analyze the attached folders. Summarize their structure and the supplied file contents, identify issues, and suggest improvements. Clearly state any coverage limits.")
    }
    static var applicationAnalysisPrompt: String {
        VyronResourceBundle.string("folderAttachmentApplicationAnalysisPrompt", fallback: "I’ve attached one or more applications.")
    }
    static func applicationOpen(_ p1: String) -> String {
        VyronResourceBundle.format(
            "folderAttachmentApplicationOpen",
            fallback: "Open %@",
            arguments: [p1]
        )
    }
    static var applicationReady: String {
        VyronResourceBundle.string("folderAttachmentApplicationReady", fallback: "Applications ready to attach")
    }
    static func applicationTooMany(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "folderAttachmentApplicationTooMany",
            fallback: "Attach up to %d applications per message.",
            arguments: [p1]
        )
    }
    static var chooseFolder: String {
        VyronResourceBundle.string("folderAttachmentChooseFolder", fallback: "Attach a folder…")
    }
    static var contextTooLarge: String {
        VyronResourceBundle.string("folderAttachmentContextTooLarge", fallback: "The attached folders and message exceed the analysis limit. Remove a folder or shorten your message.")
    }
    static var fileAnalysisPrompt: String {
        VyronResourceBundle.string("folderAttachmentFileAnalysisPrompt", fallback: "Analyze the attached files. Summarize what you can determine and mention any unavailable content.")
    }
    static var fileAudioNoTranscript: String {
        VyronResourceBundle.string("folderAttachmentFileAudioNoTranscript", fallback: "No on-device transcript is available. The model receives the name and duration.")
    }
    static func fileAudioTooLarge(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "folderAttachmentFileAudioTooLarge",
            fallback: "This audio file exceeds the %d MiB limit.",
            arguments: [p1]
        )
    }
    static var fileAudioType: String {
        VyronResourceBundle.string("folderAttachmentFileAudioType", fallback: "Audio")
    }
    static var fileAudioUnreadable: String {
        VyronResourceBundle.string("folderAttachmentFileAudioUnreadable", fallback: "This audio file could not be read. Choose a playable MP3, WAV, or M4A file.")
    }
    static var fileChoose: String {
        VyronResourceBundle.string("folderAttachmentFileChoose", fallback: "Attach files…")
    }
    static var fileContextTooLarge: String {
        VyronResourceBundle.string("folderAttachmentFileContextTooLarge", fallback: "The files exceed the analysis limit. Remove a file or shorten your message.")
    }
    static var fileDocumentNoText: String {
        VyronResourceBundle.string("folderAttachmentFileDocumentNoText", fallback: "This text file is empty.")
    }
    static func fileDocumentTooLarge(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "folderAttachmentFileDocumentTooLarge",
            fallback: "This text file exceeds the %d MiB import limit.",
            arguments: [p1]
        )
    }
    static var fileDocumentType: String {
        VyronResourceBundle.string("folderAttachmentFileDocumentType", fallback: "Text")
    }
    static var fileDocumentUnreadable: String {
        VyronResourceBundle.string("folderAttachmentFileDocumentUnreadable", fallback: "Vyron couldn’t read this text file. Choose a regular file encoded as UTF-8 or UTF-16 with a byte order mark.")
    }
    static var fileDocumentUnsupported: String {
        VyronResourceBundle.string("folderAttachmentFileDocumentUnsupported", fallback: "Choose a supported text file such as TXT, Markdown, CSV, or JSON.")
    }
    static var fileDroppedName: String {
        VyronResourceBundle.string("folderAttachmentFileDroppedName", fallback: "Dropped audio")
    }
    static var fileLimited: String {
        VyronResourceBundle.string("folderAttachmentFileLimited", fallback: "Only an excerpt will be included.")
    }
    static func filePrivacyHint(_ p1: String) -> String {
        VyronResourceBundle.format(
            "folderAttachmentFilePrivacyHint",
            fallback: "File names and available text or transcripts go to %@ when you send the message.",
            arguments: [p1]
        )
    }
    static var fileReady: String {
        VyronResourceBundle.string("folderAttachmentFileReady", fallback: "Files ready to attach")
    }
    static func fileTooMany(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "folderAttachmentFileTooMany",
            fallback: "Attach up to %d audio and text files per message.",
            arguments: [p1]
        )
    }
    static func fileUnsupported(_ p1: String) -> String {
        VyronResourceBundle.format(
            "folderAttachmentFileUnsupported",
            fallback: "This file type is unsupported: %@",
            arguments: [p1]
        )
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
    static var pdfAnalysisPrompt: String {
        VyronResourceBundle.string("folderAttachmentPdfAnalysisPrompt", fallback: "Analyze the attached material and summarize the relevant findings. Identify any limits in the supplied content.")
    }
    static var pdfChoose: String {
        VyronResourceBundle.string("folderAttachmentPdfChoose", fallback: "Attach PDFs…")
    }
    static var pdfContextTooLarge: String {
        VyronResourceBundle.string("folderAttachmentPdfContextTooLarge", fallback: "The PDFs and other draft material exceed the analysis limit. Remove an attachment or shorten your message.")
    }
    static var pdfDroppedName: String {
        VyronResourceBundle.string("folderAttachmentPdfDroppedName", fallback: "Dropped document.pdf")
    }
    static var pdfLimited: String {
        VyronResourceBundle.string("folderAttachmentPdfLimited", fallback: "Only part of this PDF’s text fits within the analysis limits.")
    }
    static var pdfNoPreview: String {
        VyronResourceBundle.string("folderAttachmentPdfNoPreview", fallback: "The first page preview is unavailable.")
    }
    static var pdfNoText: String {
        VyronResourceBundle.string("folderAttachmentPdfNoText", fallback: "This PDF has no readable text within the analysis limits. Choose a PDF with selectable text.")
    }
}
