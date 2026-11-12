import AppKit
import UniformTypeIdentifiers
import VyronCore

@MainActor
final class VyronComposerDropLoader {
    static var contentTypes: [String] { VyronScreenshotDropLoader.contentTypes }

    private let providers: [NSItemProvider]

    init(providers: [NSItemProvider]) {
        self.providers = providers
    }

    static func accepts(_ providers: [NSItemProvider]) -> Bool {
        !providers.isEmpty && providers.count <= VyronImageAttachment.maximumCount
            + AppModel.maximumFolderAttachments
            && providers.allSatisfy {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    || VyronScreenshotDropLoader.accepts([$0], remainingCapacity: 1)
            }
    }

    func load() async throws -> VyronComposerAttachments {
        guard Self.accepts(providers) else { throw VyronFolderAttachmentError.invalidFolder }
        var result = VyronComposerAttachments()
        let folders = VyronFolderAttachmentLoader()
        for provider in providers {
            try Task.checkCancellation()
            let hasPixels = VyronScreenshotDropLoader.hasImageRepresentation(provider)
            if !hasPixels, provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let data = try await VyronScreenshotDropRead(
                    provider: provider, typeIdentifier: UTType.fileURL.identifier
                ).load()
                guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                    throw VyronFolderAttachmentError.invalidFolder
                }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true || values.isSymbolicLink == true {
                    result.folders.append(try await folders.load(url))
                } else {
                    result.images.append(try await VyronScreenshotImageLoader().load(url))
                }
                continue
            }
            result.images += try await VyronScreenshotDropLoader(providers: [provider]).load()
        }
        return result
    }
}
