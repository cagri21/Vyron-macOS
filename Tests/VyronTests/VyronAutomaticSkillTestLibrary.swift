import Foundation
import VyronCore
@testable import Vyron

struct VyronAutomaticSkillTestLibrary: Sendable {
    let directory: URL
    let catalogDirectory: URL
    let installationDirectory: URL
    let localDirectory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronAutomaticSkillTests-" + UUID().uuidString)
        catalogDirectory = directory.appendingPathComponent("TrustedSkills")
        installationDirectory = directory.appendingPathComponent("ManagedSkills")
        localDirectory = directory.appendingPathComponent("UserSkills")
        try FileManager.default.createDirectory(at: catalogDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        let catalog = """
        {"version":1,"skills":[{
          "identifier":"vyron-pdf",
          "aliases":["pdf","pdf:pdf","vyron-pdf"],
          "terms":["pdf"],
          "actions":["create","make","read","review","edit","update","fill","extract","merge","split","render"]
        }]}
        """
        try catalog.write(
            to: catalogDirectory.appendingPathComponent("catalog.json"),
            atomically: true,
            encoding: .utf8
        )
        try writeSkill(
            named: "vyron-pdf",
            at: packageDirectory,
            instructions: "Use Vyron's portable PDF workflow."
        )
    }

    var packageDirectory: URL { catalogDirectory.appendingPathComponent("vyron-pdf") }
    var installedDirectory: URL { installationDirectory.appendingPathComponent("vyron-pdf") }

    func request(
        _ prompt: String,
        mode: VyronSkillSetupMode = .work,
        enabled: Bool = true
    ) -> VyronSkillContextRequest {
        VyronSkillContextRequest(
            prompt: prompt,
            roots: [VyronSkillRoot(directoryURL: localDirectory, source: .codex, scope: .personal)],
            setup: VyronSkillSetupConfiguration(
                isEnabled: enabled,
                mode: mode,
                locations: VyronSkillSetupLocations(
                    catalogDirectory: catalogDirectory,
                    installationDirectory: installationDirectory
                )
            )
        )
    }

    func writeSkill(named name: String, at destination: URL, instructions: String) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let document = "---\nname: \(name)\ndescription: A PDF workflow for this test.\n---\n\n" + instructions
        try document.write(
            to: destination.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    func cleanUp() throws {
        try FileManager.default.removeItem(at: directory)
    }
}
