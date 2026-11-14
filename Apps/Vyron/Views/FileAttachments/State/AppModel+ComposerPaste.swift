import AppKit

extension AppModel {
    func pasteComposerAttachments(
        readFileURLs: () -> [URL] = { AppModel.composerPasteFileURLs(from: .general) },
        readImageData: (NSPasteboard.PasteboardType) -> Data? = { NSPasteboard.general.data(forType: $0) }
    ) -> Bool {
        let urls = canAcceptComposerDrop ? readFileURLs() : []
        guard !urls.isEmpty else {
            return pasteScreenshotImage(reportEmptyClipboard: false, readData: readImageData)
        }
        loadComposerAttachments { try await VyronComposerFileLoader().load(urls) }
        return true
    }

    private static func composerPasteFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        guard pasteboard.types?.contains(.fileURL) == true else { return [] }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
