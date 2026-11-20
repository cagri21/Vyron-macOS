public struct VyronAutoLocalDecision: Sendable, Equatable {
    public let candidateID: String
    public let complexity: VyronAutoLocalComplexity
    public let thinkingLevel: VyronModelThinkingLevel?

    public init(
        candidateID: String,
        complexity: VyronAutoLocalComplexity,
        thinkingLevel: VyronModelThinkingLevel?
    ) {
        self.candidateID = candidateID
        self.complexity = complexity
        self.thinkingLevel = thinkingLevel
    }

    public func effectiveEffort(for requested: AgentEffort) -> AgentEffort {
        guard requested == .automatic else { return requested }
        if let thinkingLevel {
            switch thinkingLevel {
            case .low: return .quick
            case .medium: return .balanced
            case .high: return .deep
            }
        }
        switch complexity {
        case .simple: return .quick
        case .moderate: return .balanced
        case .complex: return .deep
        }
    }
}
