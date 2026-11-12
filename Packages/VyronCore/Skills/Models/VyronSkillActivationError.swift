public enum VyronSkillActivationError: Error, Sendable, Equatable {
    case unavailableDocument
    case invalidDocument
    case truncatedDocument
}
