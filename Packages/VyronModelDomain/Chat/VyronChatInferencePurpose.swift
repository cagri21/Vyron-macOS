/// Semantic intent for provider-specific request behavior; ordinary conversation remains the default.
public enum VyronChatInferencePurpose: Sendable, Equatable {
    case conversation
    case modelAssessment
}
