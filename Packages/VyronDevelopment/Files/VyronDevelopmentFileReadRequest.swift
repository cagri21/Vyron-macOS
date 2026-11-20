public struct VyronDevelopmentFileReadRequest: Sendable {
    public let path: String
    public let offset: Int

    public init(path: String, offset: Int = 0) {
        self.path = path
        self.offset = offset
    }
}
