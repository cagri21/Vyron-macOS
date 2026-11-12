public struct VyronActivityContent: Sendable, Equatable {
    public let kind: ResponseActivity.Entry.Kind
    public let title: String
    public let detail: String?
    public let category: VyronActivityCategory?

    public init(
        kind: ResponseActivity.Entry.Kind,
        title: String,
        detail: String? = nil,
        category: VyronActivityCategory? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.category = category
    }
}
