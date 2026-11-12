import AppKit
import Combine
import UniformTypeIdentifiers
import VyronCore

@MainActor
final class VyronScreenshotPreviewModel: ObservableObject {
    let image: VyronImageAttachment
    @Published private(set) var error: String?

    init(image: VyronImageAttachment) {
        self.image = image
    }

    func copyImage() {
        error = nil
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let type = NSPasteboard.PasteboardType(image.screenshotContentType.identifier)
        if !pasteboard.setData(image.data, forType: type) { error = VyronScreenshotText.copyFailed }
    }

    func saveImage() {
        error = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [image.screenshotContentType]
        let baseName = URL(fileURLWithPath: image.name).deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = baseName + "." + (image.screenshotContentType.preferredFilenameExtension ?? "png")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try image.data.write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
}
