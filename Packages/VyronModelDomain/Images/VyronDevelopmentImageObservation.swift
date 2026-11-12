/// Identifies native screenshot evidence separately from a user's authoritative message or image references.
public struct VyronDevelopmentImageObservation: Codable, Sendable, Equatable {
    public let tool: String
    public let omittedImageNames: [String]
    public let textEvidence: String?
    public let isHistorical: Bool?

    public init(
        tool: String,
        omittedImageNames: [String] = [],
        textEvidence: String? = nil,
        isHistorical: Bool = false
    ) {
        self.tool = tool
        self.omittedImageNames = Array(omittedImageNames.suffix(VyronImageAttachment.maximumCount)).map {
            boundedAgentPrefix($0, bytes: 160)
        }
        self.textEvidence = textEvidence.map(Self.boundedTextEvidence)
        self.isHistorical = isHistorical ? true : nil
    }

    private static func boundedTextEvidence(_ text: String) -> String {
        let limit = VyronDevelopmentMessageBudget.maximumToolOutputBytes
        guard text.utf8.count > limit else { return text }
        let note = "\n[Local OCR evidence truncated to fit this observation's context budget.]"
        return boundedAgentPrefix(text, bytes: limit - note.utf8.count) + note
    }
}
