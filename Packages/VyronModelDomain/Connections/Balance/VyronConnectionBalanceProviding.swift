public protocol VyronConnectionBalanceProviding: Sendable {
    func fetchBalance(
        for profile: ModelConnectionProfile,
        apiKey: String
    ) async throws -> VyronConnectionBalanceSnapshot
}
