import Foundation

struct VyronFolderAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let context: String
    let summary: VyronFolderAttachmentSummary
}
