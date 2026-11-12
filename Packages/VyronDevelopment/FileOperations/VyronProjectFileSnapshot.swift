struct VyronProjectFileSnapshot: Codable, Sendable, Equatable {
    let entries: [VyronProjectFileEntrySnapshot]
    let sourceParent: VyronProjectFileIdentity
    let destinationParent: VyronProjectFileIdentity?
    let isCaseSensitive: Bool

    private typealias CodingKeys = VyronProjectFileSnapshotCodingKeys

    init(
        entries: [VyronProjectFileEntrySnapshot],
        sourceParent: VyronProjectFileIdentity,
        destinationParent: VyronProjectFileIdentity?,
        isCaseSensitive: Bool = true
    ) {
        self.entries = entries
        self.sourceParent = sourceParent
        self.destinationParent = destinationParent
        self.isCaseSensitive = isCaseSensitive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([VyronProjectFileEntrySnapshot].self, forKey: .entries)
        sourceParent = try container.decode(VyronProjectFileIdentity.self, forKey: .sourceParent)
        destinationParent = try container.decodeIfPresent(VyronProjectFileIdentity.self, forKey: .destinationParent)
        isCaseSensitive = try container.decodeIfPresent(Bool.self, forKey: .isCaseSensitive) ?? true
    }
}
