import Foundation

enum VyronComposerFileImportError: LocalizedError {
    case unsupported(String)
    case tooMany
    case contextTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupported(let filename): VyronFolderAttachmentText.fileUnsupported(filename)
        case .tooMany: VyronFolderAttachmentText.fileTooMany(VyronFileAttachmentLimits.maximumCount)
        case .contextTooLarge: VyronFolderAttachmentText.fileContextTooLarge
        }
    }
}
