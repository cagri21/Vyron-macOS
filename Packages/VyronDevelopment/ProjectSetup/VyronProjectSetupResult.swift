public struct VyronProjectSetupResult: Sendable, Equatable {
    public let createdPaths: [String]
    public let preservedPaths: [String]

    public init(createdPaths: [String], preservedPaths: [String]) {
        self.createdPaths = createdPaths
        self.preservedPaths = preservedPaths
    }
}
