public struct VyronDevelopmentSessionGuidance: Sendable {
    public let skillContext: String?
    public let conversationSummary: String?
    public let projectInstructions: String?
    public let images: [VyronImageAttachment]

    public init(
        skillContext: String? = nil,
        conversationSummary: String? = nil,
        projectInstructions: String? = nil,
        images: [VyronImageAttachment] = []
    ) {
        self.skillContext = skillContext
        self.conversationSummary = conversationSummary
        self.projectInstructions = projectInstructions
        self.images = images
    }
}
