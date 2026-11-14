import SwiftUI

struct VyronAttachmentCardDetails {
    let name: String
    let kind: VyronAttachmentCardKind
    let helpText: String?

    var previewLabel: String {
        switch kind {
        case .pdf: VyronFolderAttachmentText.pdfPreview(name)
        case .image: VyronScreenshotText.previewImage(name)
        }
    }

    var removeLabel: String {
        switch kind {
        case .pdf: VyronFolderAttachmentText.remove(name)
        case .image: VyronScreenshotText.removeImage(name)
        }
    }
}
