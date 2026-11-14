import Foundation

enum VyronPDFAttachmentError: LocalizedError {
    case unreadable
    case tooLarge
    case noText
    case tooMany
    case contextTooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable: VyronFolderAttachmentText.pdfUnreadable
        case .tooLarge: VyronFolderAttachmentText.pdfTooLarge(
            VyronPDFAttachmentLimits.maximumImportBytes / (1_024 * 1_024)
        )
        case .noText: VyronFolderAttachmentText.pdfNoText
        case .tooMany: VyronFolderAttachmentText.pdfTooMany(VyronPDFAttachmentLimits.maximumCount)
        case .contextTooLarge: VyronFolderAttachmentText.pdfContextTooLarge
        }
    }
}
