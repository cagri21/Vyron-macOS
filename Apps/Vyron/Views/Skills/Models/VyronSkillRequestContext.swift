import VyronCore

struct VyronSkillRequestContext: Sendable {
    let text: String?
    let commands: [VyronSkillCommand]
    let catalog: [VyronSkillCommand]
    let didInstallSkills: Bool

    init(
        text: String?,
        commands: [VyronSkillCommand],
        catalog: [VyronSkillCommand] = [],
        didInstallSkills: Bool = false
    ) {
        self.text = text
        self.commands = commands
        self.catalog = catalog
        self.didInstallSkills = didInstallSkills
    }

    static let empty = Self(text: nil, commands: [])
}
