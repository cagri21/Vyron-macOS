import Foundation

enum VyronFolderAttachmentError: LocalizedError {
    case invalidFolder
    case readFailed(VyronFolderAttachmentReadFailure)

    var errorDescription: String? {
        switch self {
        case .invalidFolder: VyronFolderAttachmentText.invalidFolder
        case .readFailed(let failure): VyronFolderAttachmentText.readFailed(failure.detail)
        }
    }
}
