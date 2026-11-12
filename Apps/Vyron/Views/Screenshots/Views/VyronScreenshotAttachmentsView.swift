import AppKit
import SwiftUI
import VyronCore

struct VyronScreenshotAttachmentsView: View {
    let images: [VyronImageAttachment]
    var remove: ((UUID) -> Void)?
    @State private var preview: VyronImageAttachment?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: VyronWorkspaceStyle.controlSpacing) {
                ForEach(images) { attachment in
                    VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
                        Button {
                            preview = attachment
                        } label: {
                            if let image = NSImage(data: attachment.data) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(
                                        width: VyronScreenshotStyle.thumbnailWidth,
                                        height: VyronScreenshotStyle.thumbnailHeight
                                    )
                                    .background(Palette.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: VyronScreenshotStyle.radius))
                            }
                        }
                        .buttonStyle(.plain)
                        .help(VyronScreenshotText.preview)
                        .accessibilityLabel(VyronScreenshotText.previewImage(attachment.name))
                        HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
                            Text(verbatim: attachment.name)
                                .lineLimit(1)
                            if let remove {
                                Button { remove(attachment.id) } label: {
                                    Image(systemName: VyronSymbols.close)
                                }
                                .buttonStyle(.plain)
                                .help(VyronScreenshotText.remove)
                                .accessibilityLabel(VyronScreenshotText.removeImage(attachment.name))
                            }
                        }
                        .font(VyronWorkspaceStyle.captionFont)
                        .foregroundStyle(Palette.muted)
                        .frame(width: VyronScreenshotStyle.thumbnailWidth)
                    }
                }
            }
        }
        .sheet(item: $preview) { attachment in
            VyronScreenshotPreview(image: attachment)
        }
    }
}
