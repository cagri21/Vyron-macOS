import VyronCore

enum VyronComposerCommand: Identifiable {
    case compact
    case skill(VyronSkillCommand)

    var id: String {
        switch self {
        case .compact: "builtin:" + VyronConversationCompactionCommand.name
        case .skill(let command): command.id
        }
    }

    var name: String {
        switch self {
        case .compact: VyronConversationCompactionCommand.name
        case .skill(let command): command.name
        }
    }

    var invocation: String {
        switch self {
        case .compact: VyronConversationCompactionCommand.invocation
        case .skill(let command): command.invocation
        }
    }

    var description: String {
        switch self {
        case .compact: VyronSkillText.compactDescription
        case .skill(let command): command.skill.description
        }
    }

    var scopeLabel: String {
        switch self {
        case .compact: VyronSkillText.commandLabel
        case .skill(let command): VyronSkillLabels.scope(command.skill.scope)
        }
    }

    var help: String {
        switch self {
        case .compact: description
        case .skill(let command): command.skill.fileURL.path
        }
    }

    var skill: VyronLocalSkill? {
        switch self {
        case .compact: nil
        case .skill(let command): command.skill
        }
    }
}
