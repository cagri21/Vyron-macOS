import Foundation
import VyronModelDomain

/// JSON wire values remain separate from the semantic routing decision.
struct VyronAutoLocalResponse: Decodable {
    let candidateID: String
    let complexity: String
    let thinkingLevel: String?

    func decision(for candidate: VyronAutoLocalCandidate) throws -> VyronAutoLocalDecision {
        let semanticComplexity: VyronAutoLocalComplexity
        switch complexity {
        case "simple": semanticComplexity = .simple
        case "moderate": semanticComplexity = .moderate
        case "complex": semanticComplexity = .complex
        default: throw VyronAutoLocalRouter.invalidResponse
        }
        let level: VyronModelThinkingLevel?
        if let thinkingLevel {
            guard let requested = VyronModelThinkingLevel(rawValue: thinkingLevel) else {
                throw VyronAutoLocalRouter.invalidResponse
            }
            switch candidate.thinkingSupport {
            case .boolean: level = requested
            case .levels(let controls): level = controls.levels.contains(requested) ? requested : nil
            case .unverified, .unsupported, .providerDefaultOnly: level = nil
            }
        } else {
            level = nil
        }
        return VyronAutoLocalDecision(candidateID: candidateID, complexity: semanticComplexity, thinkingLevel: level)
    }
}
