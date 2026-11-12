import VyronModelDomain

enum VyronOllamaEffortThinking {
    static func level(
        for effort: AgentEffort,
        support: VyronModelThinkingSupport
    ) -> VyronModelThinkingLevel? {
        guard case .levels(let advertised) = support else { return nil }
        let requested: VyronModelThinkingLevel
        switch effort {
        case .automatic: return nil
        case .quick: requested = .low
        case .balanced: requested = .medium
        case .deep, .extraHigh, .maximum, .ultra: requested = .high
        }
        return advertised.levels.contains(requested) ? requested : nil
    }
}
