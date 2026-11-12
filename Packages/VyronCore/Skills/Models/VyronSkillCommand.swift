import Foundation

/// A stable, explicit invocation for one local skill document.
public struct VyronSkillCommand: Identifiable, Sendable, Equatable {
    public let name: String
    public let skill: VyronLocalSkill

    public var id: String { skill.id }
    public var invocation: String { "/" + name }

    public init(name: String, skill: VyronLocalSkill) {
        self.name = name
        self.skill = skill
    }
}
