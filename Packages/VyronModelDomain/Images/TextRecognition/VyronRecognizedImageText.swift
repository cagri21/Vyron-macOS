package struct VyronRecognizedImageText: Sendable {
    package let image: VyronImageAttachment
    package let text: String

    package init(image: VyronImageAttachment, text: String) {
        self.image = image
        self.text = text
    }
}
