struct VyronCatalogModelSelection: Sendable, Hashable {
    let role: ModelRole
    let isAutomaticCodingCandidate: Bool
    let automaticPriority: Int
    let recommendedContextTokens: Int

    init(role: ModelRole, automatic: Bool, priority: Int, context: Int = 32_768) {
        self.role = role
        isAutomaticCodingCandidate = automatic
        automaticPriority = priority
        recommendedContextTokens = context
    }
}
