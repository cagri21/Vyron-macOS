import AppKit
import SwiftUI
import VyronCore

struct VyronScreenshotPreview: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: VyronScreenshotPreviewModel

    init(image: VyronImageAttachment) {
        _model = StateObject(wrappedValue: VyronScreenshotPreviewModel(image: image))
    }

    var body: some View {
        VStack(spacing: VyronWorkspaceStyle.controlSpacing) {
            HStack {
                Text(verbatim: model.image.name).font(VyronWorkspaceStyle.inputFont)
                Spacer()
                Button(VyronScreenshotText.copyImage) { model.copyImage() }
                Button(VyronScreenshotText.saveImage) { model.saveImage() }
                Button(VyronScreenshotText.close) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let bitmap = NSImage(data: model.image.data) {
                Image(nsImage: bitmap)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(model.image.name)
            }
            if let error = model.error {
                Text(verbatim: error)
                    .font(VyronWorkspaceStyle.captionFont)
                    .foregroundStyle(Palette.warning)
                    .textSelection(.enabled)
            }
        }
        .padding(VyronScreenshotStyle.previewPadding)
        .frame(width: VyronScreenshotStyle.previewWidth, height: VyronScreenshotStyle.previewHeight)
        .background(Palette.canvas)
    }

}
