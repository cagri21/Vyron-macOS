import Foundation

/// Stable chat ownership for task checkpoints; no provider or workspace authority is stored here.
public struct VyronDevelopmentSessionContext: Sendable {
    public let conversationID: UUID
    public let responseID: UUID
    public let continuation: VyronDevelopmentContinuationContext?
    public let guidance: VyronDevelopmentSessionGuidance

    public init(
        conversationID: UUID,
        responseID: UUID,
        continuation: VyronDevelopmentContinuationContext? = nil,
        guidance: VyronDevelopmentSessionGuidance = VyronDevelopmentSessionGuidance()
    ) {
        self.conversationID = conversationID
        self.responseID = responseID
        self.continuation = continuation
        self.guidance = guidance
    }
}
