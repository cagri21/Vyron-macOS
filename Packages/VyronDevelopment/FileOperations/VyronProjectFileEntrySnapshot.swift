struct VyronProjectFileEntrySnapshot: Codable, Sendable, Equatable {
    let relativePath: String
    let isDirectory: Bool
    let identity: VyronProjectFileIdentity
    let contentHash: String?
}
