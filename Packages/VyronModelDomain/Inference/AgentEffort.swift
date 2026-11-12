import Foundation

public enum AgentEffort: String, Codable, CaseIterable, Sendable {
    case automatic = "auto"
    case quick
    case balanced
    case deep
    case extraHigh = "xhigh"
    case maximum = "max"
    case ultra

    public func resolved(for goal: String, failureCount: Int = 0) -> AgentEffort {
        guard self == .automatic else { return self }
        let text = goal.lowercased()
        let complexTerms = [
            "debug", "refactor", "compare", "research", "investigate", "analyze", "analyse", "diagnose", "troubleshoot",
            "summarize", "summarise"
        ]
        if failureCount >= 2 || goal.utf8.count > 1_500 || complexTerms.contains(where: text.contains) {
            return .deep
        }
        if failureCount > 0 { return .balanced }
        let simpleTerms = ["open ", "launch ", "activate ", "reload", "go back", "go forward"]
        if goal.count <= 160, simpleTerms.contains(where: text.hasPrefix),
            ![" and ", " then ", " after ", " until ", "\n"].contains(where: text.contains) {
            return .quick
        }
        return .balanced
    }
}
