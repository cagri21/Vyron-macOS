import Foundation

struct VyronFolderAttachmentDraft {
    let generation = UUID()
    var folders: [VyronFolderAttachment] = []
    var isLoading = false
}
