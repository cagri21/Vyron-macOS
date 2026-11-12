import Foundation

enum VyronFolderAttachmentDraftError: LocalizedError {
    case tooMany
    case contextTooLarge

    var errorDescription: String? {
        switch self {
        case .tooMany: VyronFolderAttachmentText.tooMany
        case .contextTooLarge: VyronFolderAttachmentText.contextTooLarge
        }
    }
}
