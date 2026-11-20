import Foundation
import VyronLocalization

/// A page of paths, optionally filtered by a literal, case-insensitive path substring.
public struct VyronDevelopmentFileListingRequest: Sendable {
    public let limit: Int
    public let offset: Int
    public let query: String?

    public init(limit: Int = 100, offset: Int = 0, query: String? = nil) {
        self.limit = limit
        self.offset = offset
        self.query = query
    }

    func validated() throws -> Self {
        let query = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...VyronDevelopmentFileListingLimits.maximumPageFiles).contains(limit),
            (0...VyronDevelopmentFileListingLimits.maximumInventoryFiles).contains(offset),
            self.query.map({
                $0.utf8.count <= VyronDevelopmentFileListingLimits.maximumQueryBytes
                    && !$0.contains("\0")
            }) ?? true,
            query.map({ !$0.isEmpty }) ?? true else {
            throw DevelopmentError(VyronModelDomainText.fileListingRequest)
        }
        return Self(limit: limit, offset: offset, query: query)
    }
}
