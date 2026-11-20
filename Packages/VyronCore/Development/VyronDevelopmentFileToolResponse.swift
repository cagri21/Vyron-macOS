import Foundation
import VyronDevelopment
import VyronModelDomain

enum VyronDevelopmentFileToolResponse {
    // File text is fitted before recording editing permission, so these fields never hide unread content.
    static let metadataReserveBytes = 512

    static func encode(_ page: VyronDevelopmentFilePage) throws -> String {
        let coverage = page.coverage
        let value = DevelopmentJSONValue.object([
            "ok": .bool(true), "output": .string(page.text), "truncated": .bool(!coverage.isWholeFile),
            "offset": .number(Double(coverage.offset)), "bytes_read": .number(Double(coverage.bytes)),
            "total_bytes": .number(Double(coverage.totalBytes)),
            "next_offset": coverage.nextOffset.map { .number(Double($0)) } ?? .null
        ])
        return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
