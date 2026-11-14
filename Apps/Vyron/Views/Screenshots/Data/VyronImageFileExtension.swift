import Foundation
import UniformTypeIdentifiers
import VyronCore

struct VyronImageFileExtension {
    let value: String

    init(_ attachment: VyronImageAttachment) {
        let filenameExtension = (attachment.name as NSString).pathExtension
        if VyronImageAttachment.isImageFilenameExtension(filenameExtension) {
            value = filenameExtension.uppercased()
        } else {
            value = (attachment.screenshotContentType.preferredFilenameExtension ?? "png").uppercased()
        }
    }
}
