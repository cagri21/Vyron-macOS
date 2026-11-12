public struct VyronSkillPreview: Sendable, Equatable {
    public let content: String
    public let isTruncated: Bool

    public init(content: String, isTruncated: Bool) {
        self.content = content
        self.isTruncated = isTruncated
    }
}
