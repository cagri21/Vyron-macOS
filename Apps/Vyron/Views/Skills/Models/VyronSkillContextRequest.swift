import Foundation
import VyronCore

struct VyronSkillContextRequest: Sendable {
    let prompt: String
    let roots: [VyronSkillRoot]
    let setup: VyronSkillSetupConfiguration

    init(prompt: String, roots: [VyronSkillRoot], setup: VyronSkillSetupConfiguration = .disabled) {
        self.prompt = prompt
        self.roots = roots
        self.setup = setup
    }
}
