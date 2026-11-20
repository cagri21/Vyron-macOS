public struct VyronAutoLocalRequest: Sendable {
    public let assessor: LocalModel
    public let candidates: [VyronAutoLocalCandidate]
    public let context: VyronAutoLocalContext
    public let effort: AgentEffort

    public init(
        assessor: LocalModel,
        candidates: [VyronAutoLocalCandidate],
        context: VyronAutoLocalContext,
        effort: AgentEffort
    ) {
        self.assessor = assessor
        self.candidates = candidates
        self.context = context
        self.effort = effort
    }
}
