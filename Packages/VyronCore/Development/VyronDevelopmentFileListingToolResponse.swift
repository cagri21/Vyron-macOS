import Foundation
import VyronDevelopment
import VyronModelDomain

/// Fits complete paths and their continuation cursor together; generic string truncation could hide either.
enum VyronDevelopmentFileListingToolResponse {
    static func encode(page: VyronDevelopmentFileListingPage, maximumBytes: Int) throws -> String {
        guard maximumBytes > 0 else { throw DevelopmentAgentError.contextBudget }
        var count = page.files.count
        while true {
            let files = Array(page.files.prefix(count))
            let nextOffset = count < page.files.count
                ? page.coverage.offset + count : page.coverage.nextOffset
            let output = files.map { "\($0.path) (\($0.size) bytes)" }.joined(separator: "\n")
            let value = DevelopmentJSONValue.object([
                "ok": .bool(true),
                "output": .string(output),
                "files": .array(files.map {
                    .object(["path": .string($0.path), "size": .number(Double($0.size))])
                }),
                "offset": .number(Double(page.coverage.offset)),
                "next_offset": nextOffset.map { .number(Double($0)) } ?? .null,
                "total_matches": .number(Double(page.coverage.totalMatches)),
                "scan_limited": .bool(page.coverage.scanLimited),
                "truncated": .bool(nextOffset != nil || page.coverage.scanLimited)
            ])
            let data = try JSONEncoder().encode(value)
            if data.count <= maximumBytes, count > 0 || page.files.isEmpty {
                return String(decoding: data, as: UTF8.self)
            }
            // A zero-entry page with the same cursor would never advance discovery.
            guard count > 1 else { throw DevelopmentAgentError.contextBudget }
            count -= 1
        }
    }
}
