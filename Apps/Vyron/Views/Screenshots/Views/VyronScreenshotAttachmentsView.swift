import SwiftUI
import VyronCore

struct VyronScreenshotAttachmentsView: View {
    let images: [VyronImageAttachment]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: VyronWorkspaceStyle.controlSpacing) {
                ForEach(images) { attachment in
                    VyronScreenshotAttachmentCard(attachment: attachment)
                }
            }
        }
    }
}
