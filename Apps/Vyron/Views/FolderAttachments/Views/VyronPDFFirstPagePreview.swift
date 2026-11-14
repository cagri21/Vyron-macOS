import AppKit
import SwiftUI
import VyronModelDomain

struct VyronPDFFirstPagePreview: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: VyronPDFPreview

    var body: some View {
        VStack(spacing: VyronWorkspaceStyle.controlSpacing) {
            HStack {
                Text(verbatim: attachment.name)
                    .font(VyronWorkspaceStyle.inputFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(VyronScreenshotText.close) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            if let imageData = attachment.imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(VyronFolderAttachmentText.pdfPreview(attachment.name))
            } else {
                Text(VyronFolderAttachmentText.pdfNoPreview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(VyronScreenshotStyle.previewPadding)
        .frame(width: VyronScreenshotStyle.previewWidth, height: VyronScreenshotStyle.previewHeight)
        .background(Palette.canvas)
    }
}
