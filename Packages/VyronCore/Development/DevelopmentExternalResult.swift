public struct DevelopmentExternalResult: Sendable {
    public let text: String
    public let isError: Bool
    public let images: [VyronImageAttachment]

    public init(text: String, isError: Bool = false, images: [VyronImageAttachment] = []) {
        self.text = text
        self.isError = isError
        self.images = images
    }
}
