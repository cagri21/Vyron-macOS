import UniformTypeIdentifiers
import VyronCore

extension VyronImageAttachment {
    private static let rasterFilenameExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tif", "tiff", "heic", "heif", "gif", "webp", "bmp"
    ]

    var screenshotContentType: UTType {
        switch mimeType {
        case "image/jpeg": .jpeg
        case "image/webp": .webP
        default: .png
        }
    }

    static func isImageFilenameExtension(_ filenameExtension: String) -> Bool {
        guard !filenameExtension.isEmpty else { return false }
        // Standard raster types remain usable when the system type registry is unavailable.
        return rasterFilenameExtensions.contains(filenameExtension.lowercased())
            || UTType(filenameExtension: filenameExtension)?.conforms(to: .image) == true
    }
}
