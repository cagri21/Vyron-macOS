import Foundation
import ImageIO
import UniformTypeIdentifiers
import VyronCore

actor VyronScreenshotImageLoader {
    func load(_ url: URL) throws -> VyronImageAttachment {
        try Task.checkCancellation()
        guard url.isFileURL else { throw VyronScreenshotImportError.invalidImage }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw VyronScreenshotImportError.invalidImage }
        guard let size = values.fileSize, size <= VyronScreenshotLimits.maximumImportBytes else {
            throw VyronScreenshotImportError.tooLarge
        }
        return try load(Data(contentsOf: url), name: url.lastPathComponent)
    }

    func load(_ data: Data, name: String) throws -> VyronImageAttachment {
        try Task.checkCancellation()
        guard data.count <= VyronScreenshotLimits.maximumImportBytes else {
            throw VyronScreenshotImportError.tooLarge
        }
        guard !data.isEmpty,
            let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(source) > 0
        else { throw VyronScreenshotImportError.invalidImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: VyronScreenshotLimits.maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw VyronScreenshotImportError.invalidImage
        }
        try Task.checkCancellation()
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw VyronScreenshotImportError.invalidImage
        }
        // Re-encode pixels only: imported location and camera metadata do not accompany the screenshot.
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw VyronScreenshotImportError.invalidImage }
        let normalized = output as Data
        guard normalized.count <= VyronImageAttachment.maximumDataBytes else {
            throw VyronScreenshotImportError.tooLarge
        }
        try Task.checkCancellation()
        return VyronImageAttachment(name: name, mimeType: "image/png", data: normalized)
    }
}
