import VyronCore

enum VyronTrackedRunEvent: Sendable {
    case development(DevelopmentEvent)
    case subagent(VyronSubagentEvent)
}
