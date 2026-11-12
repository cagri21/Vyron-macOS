import Foundation
import VyronCore
import VyronModelDomain

@MainActor
final class VyronForegroundSteering {
    let inbox: VyronSteeringInbox
    let skills: VyronSkillResourceTools
    var pendingMessageIDs: Set<UUID> = []

    init(inbox: VyronSteeringInbox, skills: VyronSkillResourceTools) {
        self.inbox = inbox
        self.skills = skills
    }
}
