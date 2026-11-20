import VyronCore

struct VyronComposerSkillMention {
    let command: VyronSkillCommand
    let prefix: String
    let text: String

    var label: String {
        command.skill.name.split(separator: "-").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
