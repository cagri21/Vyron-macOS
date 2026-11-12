enum VyronOllamaPlanningLimits {
    static let contextTokens = 32_768
    static let controlOutputTokens = 512
    static let controlSnapshotBytes = 12_000
    static let controlProposalAttempts = 2
    static let invalidProposalFeedbackBytes = 6_000
    static let maximumResponseBytes = 65_536
    static let maximumResponseContentBytes = 24_000

    static let maximumCandidateApplications = 256
    static let maximumSuppliedApplications = 64
    static let applicationNameBytes = 80
    static let applicationCatalogBytes = 6_000
    static let agentPromptOverheadBytes = 512
}
