import AppKit
import SwiftUI

struct VyronAttachmentPreviewCard<Preview: View>: View {
    @Environment(\.vyronPalette) private var palette
    let details: VyronAttachmentCardDetails
    let imageData: Data?
    let remove: (() -> Void)?
    @ViewBuilder let preview: () -> Preview

    @State private var showsPreview = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VyronScreenshotStyle.radius)
        ZStack(alignment: .topTrailing) {
            previewButton(in: shape)
            if let remove {
                Button(action: remove) {
                    Image(systemName: VyronSymbols.close)
                        .font(VyronWorkspaceStyle.captionFont.weight(.semibold))
                        .foregroundStyle(palette.text)
                        .frame(
                            width: VyronScreenshotStyle.removeButtonSize,
                            height: VyronScreenshotStyle.removeButtonSize
                        )
                        .background(palette.canvas, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(details.removeLabel)
                .accessibilityLabel(details.removeLabel)
                .padding(VyronWorkspaceStyle.compactSpacing)
            }
        }
        .overlay { shape.strokeBorder(palette.border).allowsHitTesting(false).accessibilityHidden(true) }
        .sheet(isPresented: $showsPreview, content: preview)
    }

    private func previewButton(in shape: RoundedRectangle) -> some View {
        Button { showsPreview = true } label: {
            VStack(spacing: 0) {
                thumbnail
                footer
            }
            .frame(width: VyronScreenshotStyle.thumbnailWidth)
            .background(palette.canvas)
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help([details.name, details.helpText].compactMap { $0 }.joined(separator: "\n"))
        .accessibilityLabel(details.previewLabel)
        .accessibilityValue(details.kind.typeLabel)
    }

    private var thumbnail: some View {
        Group {
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: thumbnailContentMode)
            } else {
                Image(systemName: details.kind.symbol)
                    .font(VyronWorkspaceStyle.inputFont)
                    .foregroundStyle(details.kind.tint(in: palette))
            }
        }
        .frame(width: VyronScreenshotStyle.thumbnailWidth, height: VyronScreenshotStyle.thumbnailHeight, alignment: .top)
        .clipped()
        .background(palette.surface)
        .accessibilityHidden(true)
    }

    private var thumbnailContentMode: ContentMode {
        switch details.kind {
        case .pdf: .fill
        case .image: .fit
        }
    }

    private var footer: some View {
        HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
            Image(systemName: details.kind.symbol)
                .foregroundStyle(details.kind.tint(in: palette))
            Text(verbatim: details.kind.typeLabel)
                .font(VyronWorkspaceStyle.captionFont.weight(.semibold))
                .foregroundStyle(details.kind.tint(in: palette))
                .lineLimit(1)
                .frame(maxWidth: VyronScreenshotStyle.typeBadgeTextMaximumWidth)
                .fixedSize(horizontal: true, vertical: false)
            Text(verbatim: details.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(VyronWorkspaceStyle.controlFont)
        .foregroundStyle(palette.text)
        .padding(VyronWorkspaceStyle.compactSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
