public enum VyronSubagentUpdate: Sendable {
    case started
    case activity(DevelopmentEvent)
    case finished(VyronSubagentCompletion)
}
