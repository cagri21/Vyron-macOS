import VyronCore

enum VyronSkillLabels {
    static func source(_ source: VyronSkillSource) -> String {
        switch source {
        case .codex: VyronSkillText.codex
        case .claude: VyronSkillText.claude
        case .agents: VyronSkillText.shared
        }
    }

    static func scope(_ scope: VyronSkillScope) -> String {
        switch scope {
        case .personal: VyronSkillText.personal
        case .project: VyronSkillText.project
        case .plugin: VyronSkillText.plugin
        }
    }
}
