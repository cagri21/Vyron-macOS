import Foundation
import VyronCore

struct VyronSkillSetupConfiguration: Sendable {
    let isEnabled: Bool
    let mode: VyronSkillSetupMode
    let locations: VyronSkillSetupLocations?
    let installer: VyronSkillInstaller

    init(
        isEnabled: Bool,
        mode: VyronSkillSetupMode,
        locations: VyronSkillSetupLocations?,
        installer: VyronSkillInstaller = VyronSkillInstaller()
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.locations = locations
        self.installer = installer
    }

    static let disabled = Self(isEnabled: false, mode: .chat, locations: nil)

    var permitsAutomaticSetup: Bool { isEnabled && mode == .work && locations != nil }

    func discoveryRoots(adding roots: [VyronSkillRoot]) -> [VyronSkillRoot] {
        guard let directory = locations?.installationDirectory,
            !roots.contains(where: { $0.directoryURL == directory })
        else { return roots }
        return [VyronSkillRoot(directoryURL: directory, source: .agents, scope: .personal)] + roots
    }

    static func current(mode: ComposerMode, homeDirectory: URL) -> Self {
        let setupMode: VyronSkillSetupMode = switch mode {
        case .agent: .work
        case .plan: .plan
        case .chat: .chat
        }
        let locations = Bundle.module.url(forResource: "TrustedSkills", withExtension: nil).map {
            VyronSkillSetupLocations(
                catalogDirectory: $0,
                installationDirectory: homeDirectory.appendingPathComponent(
                    "Library/Application Support/VyronAI/Skills", isDirectory: true
                )
            )
        }
        return Self(
            isEnabled: VyronSkillSetupPreferences.isEnabled,
            mode: setupMode,
            locations: locations,
            installer: VyronSkillInstaller()
        )
    }
}
