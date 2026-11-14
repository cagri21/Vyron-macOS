import AppKit
import UniformTypeIdentifiers
import VyronCore

@MainActor
final class VyronScreenshotDropLoader {
    private static let rasterTypeIdentifiers = [
        UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier, UTType.heic.identifier,
        UTType.heif.identifier, UTType.gif.identifier, UTType.webP.identifier, UTType.bmp.identifier
    ]
    static var contentTypes: [String] {
        [UTType.fileURL.identifier, UTType.image.identifier] + rasterTypeIdentifiers
    }

    private let providers: [NSItemProvider]

    init(providers: [NSItemProvider]) {
        self.providers = providers
    }

    static func accepts(_ providers: [NSItemProvider], remainingCapacity: Int) -> Bool {
        !providers.isEmpty && providers.count <= remainingCapacity && providers.allSatisfy(canLoad)
    }

    static func hasImageRepresentation(_ provider: NSItemProvider) -> Bool {
        imageType(for: provider) != nil
    }

    func load() async throws -> [VyronImageAttachment] {
        guard Self.accepts(providers, remainingCapacity: VyronImageAttachment.maximumCount) else {
            throw VyronScreenshotImportError.invalidImage
        }
        let loader = VyronScreenshotImageLoader()
        var images: [VyronImageAttachment] = []
        for provider in providers {
            try Task.checkCancellation()
            let image = try await load(provider, using: loader)
            guard images.reduce(image.data.count, { $0 + $1.data.count })
                <= VyronImageAttachment.maximumRequestDataBytes
            else { throw VyronScreenshotImportError.tooLarge }
            images.append(image)
        }
        return images
    }

    private static func canLoad(_ provider: NSItemProvider) -> Bool {
        if imageType(for: provider) != nil { return true }
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return false }
        guard let name = provider.suggestedName else { return true }
        let extensionName = URL(fileURLWithPath: name).pathExtension
        return extensionName.isEmpty || VyronImageAttachment.isImageFilenameExtension(extensionName)
    }

    private static func imageType(for provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first {
            // Standard raster types remain usable when the system type registry is unavailable.
            $0 == UTType.image.identifier || rasterTypeIdentifiers.contains($0)
                || UTType($0)?.conforms(to: .image) == true
        }
    }

    private func load(
        _ provider: NSItemProvider,
        using loader: VyronScreenshotImageLoader
    ) async throws -> VyronImageAttachment {
        if let typeIdentifier = Self.imageType(for: provider) {
            let data = try await VyronScreenshotDropRead(provider: provider, typeIdentifier: typeIdentifier).load()
            let name = provider.suggestedName ?? VyronScreenshotText.droppedImage
            return try await loader.load(data, name: name)
        }
        let data = try await VyronScreenshotDropRead(
            provider: provider, typeIdentifier: UTType.fileURL.identifier
        ).load()
        guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL,
            VyronImageAttachment.isImageFilenameExtension(url.pathExtension)
        else { throw VyronScreenshotImportError.invalidImage }
        return try await loader.load(url)
    }
}
