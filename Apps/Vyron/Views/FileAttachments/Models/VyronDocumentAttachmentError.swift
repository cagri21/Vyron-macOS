import Foundation

enum VyronDocumentAttachmentError: LocalizedError, Equatable {
    case unsupported
    case unreadable
    case tooLarge
    case noText

    var errorDescription: String? {
        switch self {
        case .unsupported: VyronFolderAttachmentText.fileDocumentUnsupported
        case .unreadable: VyronFolderAttachmentText.fileDocumentUnreadable
        case .tooLarge: VyronFolderAttachmentText.fileDocumentTooLarge(
            VyronDocumentAttachmentLimits.maximumImportBytes / VyronDocumentAttachmentLimits.bytesPerMebibyte
        )
        case .noText: VyronFolderAttachmentText.fileDocumentNoText
        }
    }
}
