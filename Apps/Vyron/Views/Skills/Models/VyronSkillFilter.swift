import VyronCore

enum VyronSkillFilter: CaseIterable, Hashable {
    case all
    case codex
    case claude
    case shared

    var title: String {
        switch self {
        case .all: VyronSkillText.all
        case .codex: VyronSkillText.codex
        case .claude: VyronSkillText.claude
        case .shared: VyronSkillText.shared
        }
    }

    func includes(_ source: VyronSkillSource) -> Bool {
        switch self {
        case .all: true
        case .codex: source == .codex
        case .claude: source == .claude
        case .shared: source == .agents
        }
    }
}
