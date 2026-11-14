import Foundation

/// Local transcript metadata. Inference receives a bounded text reference separately.
package struct VyronFileAttachmentInfo: Identifiable, Codable, Sendable, Equatable {
    package let id: UUID
    package let name: String
    package let kind: VyronFileAttachmentKind
    package let duration: TimeInterval?
    package var hasTranscript: Bool?

    package init(id: UUID = UUID(), name: String, kind: VyronFileAttachmentKind, duration: TimeInterval? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.duration = duration
    }
}
