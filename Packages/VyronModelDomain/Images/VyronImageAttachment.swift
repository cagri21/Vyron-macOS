import Foundation

/// An explicitly attached image. Provider-specific encoding belongs to the model adapters.
public struct VyronImageAttachment: Identifiable, Codable, Sendable, Equatable {
    static let bytesPerMebibyte = 1_024 * 1_024
    public static let maximumCount = 4
    public static let maximumDataBytes = 8 * bytesPerMebibyte
    public static let maximumRequestDataBytes = 16 * bytesPerMebibyte
    /// A bounded reservation, independent of base64 size. Actual model image costs vary.
    public static let estimatedContextTokens = 4_096

    public let id: UUID
    public let name: String
    public let mimeType: String
    public let data: Data

    public init(id: UUID = UUID(), name: String, mimeType: String, data: Data) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.data = data
    }

    public static func validate(messages: [ChatMessage]) throws {
        var count = 0
        var bytes = 0
        for message in messages {
            let images = message.images ?? []
            guard images.isEmpty || message.role == "user" else {
                throw VyronImageAttachmentError.invalidRole
            }
            count += images.count
            guard count <= maximumCount else { throw VyronImageAttachmentError.tooManyImages }
            for image in images {
                guard !image.data.isEmpty, image.data.count <= maximumDataBytes else {
                    throw VyronImageAttachmentError.invalidSize
                }
                bytes += image.data.count
                guard bytes <= maximumRequestDataBytes else { throw VyronImageAttachmentError.requestTooLarge }
                guard image.hasMatchingFormat else { throw VyronImageAttachmentError.unsupportedFormat }
            }
        }
    }

    private var hasMatchingFormat: Bool {
        switch mimeType {
        case "image/png":
            data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        case "image/jpeg":
            data.starts(with: [0xFF, 0xD8, 0xFF])
        case "image/webp":
            data.starts(with: Array("RIFF".utf8)) && data.dropFirst(8).starts(with: Array("WEBP".utf8))
        default:
            false
        }
    }
}
