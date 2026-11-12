import UniformTypeIdentifiers
import VyronCore

extension VyronImageAttachment {
    var screenshotContentType: UTType {
        switch mimeType {
        case "image/jpeg": .jpeg
        case "image/webp": .webP
        default: .png
        }
    }
}
