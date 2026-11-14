import VyronCore

enum VyronComposerCommand: Identifiable {
    case compact
    case side
    case skill(VyronSkillCommand)

    var id: String {
        switch self {
        case .compact: "builtin:" + VyronConversationCompactionCommand.name
        case .side: "builtin:" + VyronSideChatCommand.name
        case .skill(let command): command.id
        }
    }

    var name: String {
        switch self {
        case .compact: VyronConversationCompactionCommand.name
        case .side: VyronSideChatCommand.name
        case .skill(let command): command.name
        }
    }

    var invocation: String {
        switch self {
        case .compact: VyronConversationCompactionCommand.invocation
        case .side: VyronSideChatCommand.invocation
        case .skill(let command): command.invocation
        }
    }

    var description: String {
        switch self {
        case .compact: VyronSkillText.compactDescription
        case .side: VyronSkillText.sideDescription
        case .skill(let command): command.skill.description
        }
    }

    var scopeLabel: String {
        switch self {
        case .compact, .side: VyronSkillText.commandLabel
        case .skill(let command): VyronSkillLabels.scope(command.skill.scope)
        }
    }

    var help: String {
        switch self {
        case .compact, .side: description
        case .skill(let command): command.skill.fileURL.path
        }
    }

    var skill: VyronLocalSkill? {
        switch self {
        case .compact, .side: nil
        case .skill(let command): command.skill
        }
    }
}
