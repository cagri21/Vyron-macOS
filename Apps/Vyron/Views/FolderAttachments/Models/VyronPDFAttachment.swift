import Foundation
import VyronModelDomain

struct VyronPDFAttachment: Identifiable, Equatable, Sendable {
    var id: UUID { preview.id }
    let preview: VyronPDFPreview
    let text: String
    let isTruncated: Bool
}
