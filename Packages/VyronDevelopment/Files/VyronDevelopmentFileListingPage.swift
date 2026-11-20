public struct VyronDevelopmentFileListingPage: Sendable {
    public let files: [DevelopmentFile]
    public let coverage: VyronDevelopmentFileListingCoverage

    public init(files: [DevelopmentFile], coverage: VyronDevelopmentFileListingCoverage) {
        self.files = files
        self.coverage = coverage
    }
}
