public struct VyronSkillDiscoveryLimits: Sendable, Equatable {
    public let maximumEntries: Int
    public let maximumSkills: Int
    public let maximumDepth: Int
    public let maximumDocumentBytes: Int

    public init(
        maximumEntries: Int = 30_000,
        maximumSkills: Int = 1_000,
        maximumDepth: Int = 10,
        maximumDocumentBytes: Int = 65_536
    ) {
        self.maximumEntries = max(1, maximumEntries)
        self.maximumSkills = max(1, maximumSkills)
        self.maximumDepth = max(1, maximumDepth)
        self.maximumDocumentBytes = min(1_048_576, max(1, maximumDocumentBytes))
    }
}
