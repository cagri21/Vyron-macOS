public enum VyronConversationCompactionError: Error, Sendable, Equatable {
    case invalidSummary
    case summaryTooLarge
    case inputTooLarge
}
