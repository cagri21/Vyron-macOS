public struct VyronDevelopmentSessionGuidance: Sendable {
    public let skillContext: String?
    public let conversationSummary: String?
    public private(set) var projectInstructions: String?
    public let images: [VyronImageAttachment]
    package var attachmentReference: String?

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

    func withProjectInstructions(_ instructions: String?) -> Self {
        var guidance = self
        guidance.projectInstructions = instructions
        return guidance
    }
}
