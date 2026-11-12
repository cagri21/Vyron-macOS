import CryptoKit
import Foundation

struct VyronDevelopmentFileProgress: Codable, Sendable, Equatable {
    let path: String
    let contentHash: String
    let status: VyronDevelopmentFileStatus
    let recordedAt: Date

    init(path: String, contentHash: String, status: VyronDevelopmentFileStatus = .saved, recordedAt: Date = Date()) {
        self.path = path
        self.contentHash = contentHash
        self.status = status
        self.recordedAt = recordedAt
    }

    static func hash(content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func matches(content: String) -> Bool { contentHash == Self.hash(content: content) }
}
