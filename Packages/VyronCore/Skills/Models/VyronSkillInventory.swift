public struct VyronSkillInventory: Sendable, Equatable {
    public let skills: [VyronLocalSkill]
    public let issues: [VyronSkillDiscoveryIssue]
    public let didReachLimit: Bool

    public init(skills: [VyronLocalSkill], issues: [VyronSkillDiscoveryIssue], didReachLimit: Bool) {
        self.skills = skills
        self.issues = issues
        self.didReachLimit = didReachLimit
    }
}
