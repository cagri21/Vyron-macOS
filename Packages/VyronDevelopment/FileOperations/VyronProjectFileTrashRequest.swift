public struct VyronProjectFileTrashRequest: Codable, Sendable, Equatable {
    public let path: String

    public init(path: String) { self.path = path }
}
