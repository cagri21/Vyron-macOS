import Foundation
import VyronCore

enum VyronAutomaticSkillSetup {
    static func prepare(
        _ request: VyronSkillContextRequest,
        commands: VyronSkillCommands,
        discoveredSkills: [VyronLocalSkill]
    ) async throws -> VyronSkillSetupSelection {
        guard let locations = request.setup.locations else {
            return VyronSkillSetupSelection(identifiers: [], didInstallSkills: false)
        }
        let names = VyronSkillCommands.invokedNames(in: request.prompt).map { $0.lowercased() }
        let missingNames = names.filter { name in !commands.entries.contains { $0.name == name } }
        if names.isEmpty, !request.setup.permitsAutomaticSetup {
            return VyronSkillSetupSelection(identifiers: [], didInstallSkills: false)
        }
        if !names.isEmpty, missingNames.isEmpty {
            return VyronSkillSetupSelection(identifiers: [], didInstallSkills: false)
        }
        do {
            try Task.checkCancellation()
            let catalog = try VyronSkillSetupCatalog.read(from: locations.catalogDirectory)
            let selected = catalog.skills.filter { entry in
                let matches = names.isEmpty
                    ? entry.matches(request.prompt)
                    : missingNames.contains { name in entry.aliases.contains(name) }
                return matches && (
                    request.setup.permitsAutomaticSetup
                        || managedCommand(identifier: entry.identifier, locations: locations, commands: commands) != nil
                )
            }
            try validateNames(selected, locations: locations, discoveredSkills: discoveredSkills)
            var didInstall = false
            for entry in selected {
                try Task.checkCancellation()
                if managedCommand(identifier: entry.identifier, locations: locations, commands: commands) != nil {
                    continue
                }
                _ = try await request.setup.installer.install(VyronSkillInstallRequest(
                    packageDirectory: locations.catalogDirectory.appendingPathComponent(entry.identifier),
                    installationDirectory: locations.installationDirectory,
                    identifier: entry.identifier
                ))
                try Task.checkCancellation()
                didInstall = true
            }
            return VyronSkillSetupSelection(identifiers: selected.map(\.identifier), didInstallSkills: didInstall)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VyronSkillSetupError {
            throw error
        } catch {
            throw VyronSkillSetupError.failed
        }
    }

    private static func validateNames(
        _ selected: [VyronSkillSetupCatalogEntry],
        locations: VyronSkillSetupLocations,
        discoveredSkills: [VyronLocalSkill]
    ) throws {
        for entry in selected {
            let file = locations.installationDirectory.appendingPathComponent(entry.identifier)
                .appendingPathComponent("SKILL.md").standardizedFileURL
            guard !discoveredSkills.contains(where: { skill in
                guard skill.fileURL.standardizedFileURL != file else { return false }
                return skill.name == entry.identifier
                    || VyronSkillCommands(skills: [skill]).entries.first?.name == entry.identifier
            }) else { throw VyronSkillSetupError.nameConflict }
        }
    }

    static func managedCommand(
        identifier: String,
        locations: VyronSkillSetupLocations,
        commands: VyronSkillCommands
    ) -> VyronSkillCommand? {
        let file = locations.installationDirectory.appendingPathComponent(identifier)
            .appendingPathComponent("SKILL.md").standardizedFileURL
        return commands.entries.first { $0.skill.fileURL.standardizedFileURL == file }
    }
}
