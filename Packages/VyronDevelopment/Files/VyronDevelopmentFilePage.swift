public struct VyronDevelopmentFilePage: Sendable {
    public let text: String
    public let coverage: VyronDevelopmentFileReadCoverage

    public init(text: String, coverage: VyronDevelopmentFileReadCoverage) {
        self.text = text
        self.coverage = coverage
    }
}
