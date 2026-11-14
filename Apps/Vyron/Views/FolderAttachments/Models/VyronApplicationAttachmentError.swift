import Foundation

enum VyronApplicationAttachmentError: LocalizedError {
    case tooMany

    var errorDescription: String? {
        VyronFolderAttachmentText.applicationTooMany(AppModel.maximumApplicationAttachments)
    }
}
