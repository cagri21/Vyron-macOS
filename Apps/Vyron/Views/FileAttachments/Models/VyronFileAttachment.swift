import Foundation
import VyronModelDomain

struct VyronFileAttachment: Identifiable, Sendable {
    var id: UUID { info.id }
    let info: VyronFileAttachmentInfo
    let text: String?
    let isTruncated: Bool

    init(info: VyronFileAttachmentInfo, text: String?, isTruncated: Bool = false) {
        var info = info
        if info.kind == .audio { info.hasTranscript = text != nil }
        self.info = info
        self.text = text
        self.isTruncated = isTruncated
    }
}
