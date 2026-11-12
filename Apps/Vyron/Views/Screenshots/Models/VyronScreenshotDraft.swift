import Foundation
import VyronCore

struct VyronScreenshotDraft {
    let generation = UUID()
    var images: [VyronImageAttachment] = []
    var isLoading = false
}
