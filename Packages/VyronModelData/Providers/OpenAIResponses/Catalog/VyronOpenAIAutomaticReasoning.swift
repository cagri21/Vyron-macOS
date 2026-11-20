import VyronModelDomain

/// Auto Local opts into the common reasoning levels of the exact official Responses families.
/// Ordinary model selections and unknown model identifiers keep provider defaults.
enum VyronOpenAIAutomaticReasoning {
    static func effort(for model: String, effort: AgentEffort, enabled: Bool) -> String? {
        guard enabled, VyronOpenAIResponsesRoute.modelFamily(for: model) != nil else { return nil }
        switch effort {
        case .automatic: return nil
        case .quick: return "low"
        case .balanced: return "medium"
        case .deep, .extraHigh, .maximum, .ultra: return "high"
        }
    }
}
