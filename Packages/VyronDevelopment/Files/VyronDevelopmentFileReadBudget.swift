public struct VyronDevelopmentFileReadBudget: Sendable {
    public static let maximumFileBytes = 512_000
    public let maximumTextBytes: Int
    public let maximumEncodedTextBytes: Int

    public init(maximumTextBytes: Int = 40_000, maximumEncodedTextBytes: Int = .max) {
        self.maximumTextBytes = maximumTextBytes
        self.maximumEncodedTextBytes = maximumEncodedTextBytes
    }
}
