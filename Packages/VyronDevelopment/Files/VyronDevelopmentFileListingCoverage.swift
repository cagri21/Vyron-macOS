/// Counts describe the bounded matching inventory; scanLimited means additional matches may exist.
public struct VyronDevelopmentFileListingCoverage: Sendable, Encodable {
    public let offset: Int
    public let nextOffset: Int?
    public let totalMatches: Int
    public let scanLimited: Bool

    public init(offset: Int, nextOffset: Int?, totalMatches: Int, scanLimited: Bool) {
        self.offset = offset
        self.nextOffset = nextOffset
        self.totalMatches = totalMatches
        self.scanLimited = scanLimited
    }
}
