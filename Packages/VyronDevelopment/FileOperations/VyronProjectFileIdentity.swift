struct VyronProjectFileIdentity: Codable, Sendable, Equatable {
    let device: UInt64
    let inode: UInt64
    let revision: String
    let stableRevision: String
}
