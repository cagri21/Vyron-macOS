import Foundation

enum VyronAudioAttachmentError: LocalizedError {
    case unreadable
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable: VyronFolderAttachmentText.fileAudioUnreadable
        case .tooLarge: VyronFolderAttachmentText.fileAudioTooLarge(VyronAudioAttachmentLimits.maximumImportMiB)
        }
    }
}
