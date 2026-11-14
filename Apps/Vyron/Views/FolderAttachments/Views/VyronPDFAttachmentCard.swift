import SwiftUI
import VyronModelDomain

struct VyronPDFAttachmentCard: View {
    let attachment: VyronPDFPreview
    var helpText: String?
    var remove: ((UUID) -> Void)?

    var body: some View {
        VyronAttachmentPreviewCard(
            details: .init(name: attachment.name, kind: .pdf, helpText: helpText),
            imageData: attachment.imageData,
            remove: remove.map { action in { action(attachment.id) } }
        ) {
            VyronPDFFirstPagePreview(attachment: attachment)
        }
    }
}
