import Foundation
import VyronModelDomain

struct VyronDeepSeekRequestConfiguration: Sendable {
    let enabled: Bool
    let effort: String

    init(settings: ModelSettings, effort: AgentEffort) {
        enabled = settings.thinking ?? true
        switch effort {
        case .quick: self.effort = "low"
        case .automatic, .balanced, .deep, .extraHigh: self.effort = "high"
        case .maximum, .ultra: self.effort = "max"
        }
    }
}
