import AppKit
import SwiftUI
import VyronCore

struct VyronSentImageThumbnail: View {
    @Environment(\.vyronPalette) private var palette
    @State private var showsPreview = false
    let attachment: VyronImageAttachment

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VyronConversationStyle.sentImageRadius)
        Button { showsPreview = true } label: {
            thumbnail
                .frame(width: VyronConversationStyle.sentImageSize, height: VyronConversationStyle.sentImageSize)
                .background(palette.surface)
                .clipShape(shape)
                .overlay { shape.strokeBorder(palette.border) }
                .contentShape(shape)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .help(attachment.name)
        .accessibilityLabel(VyronScreenshotText.previewImage(attachment.name))
        .accessibilityValue(VyronImageFileExtension(attachment).value)
        .sheet(isPresented: $showsPreview) {
            VyronScreenshotPreview(image: attachment)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = NSImage(data: attachment.data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: VyronSymbols.screenshot)
                .font(VyronWorkspaceStyle.inputFont)
                .foregroundStyle(palette.muted)
        }
    }
}
