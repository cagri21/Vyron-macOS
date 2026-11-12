struct VyronProjectFileJournalIdentity: Codable, Sendable {
    let rootPath: String
    let operation: VyronPreparedProjectFileOperation
}
