public struct VyronDevelopmentFileReadCoverage: Sendable, Encodable {
    public let offset: Int
    public let bytes: Int
    public let totalBytes: Int

    public init(offset: Int, bytes: Int, totalBytes: Int) {
        self.offset = offset
        self.bytes = bytes
        self.totalBytes = totalBytes
    }

    public var nextOffset: Int? { offset + bytes < totalBytes ? offset + bytes : nil }
    public var isWholeFile: Bool { offset == 0 && bytes == totalBytes }
}
