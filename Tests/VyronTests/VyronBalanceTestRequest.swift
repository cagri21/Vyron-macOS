import VyronCore

struct VyronBalanceTestRequest: Sendable {
    let profile: ModelConnectionProfile
    let usedFixtureCredential: Bool
}
