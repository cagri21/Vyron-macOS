import SwiftUI
import VyronCore

struct VyronScreenshotAttachmentCard: View {
    let attachment: VyronImageAttachment
    let helpText: String?
    let remove: ((UUID) -> Void)?

    init(attachment: VyronImageAttachment, helpText: String? = nil, remove: ((UUID) -> Void)? = nil) {
        self.attachment = attachment
        self.helpText = helpText
        self.remove = remove
    }

    var body: some View {
        let details = VyronAttachmentCardDetails(
            name: attachment.name, kind: .image(VyronImageFileExtension(attachment)), helpText: helpText
        )
        VyronAttachmentPreviewCard(
            details: details,
            imageData: attachment.data,
            remove: remove.map { action in { action(attachment.id) } }
        ) {
            VyronScreenshotPreview(image: attachment)
        }
    }
}
