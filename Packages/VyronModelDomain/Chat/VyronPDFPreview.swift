import Foundation

/// Local attachment metadata for the transcript. Provider requests use the extracted text separately.
package struct VyronPDFPreview: Identifiable, Codable, Sendable, Equatable {
    package let id: UUID
    package let name: String
    package let imageData: Data?

    package init(id: UUID = UUID(), name: String, imageData: Data?) {
        self.id = id
        self.name = name
        self.imageData = imageData
    }
}
