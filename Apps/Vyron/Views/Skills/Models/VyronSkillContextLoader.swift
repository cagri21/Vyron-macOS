import Foundation
import VyronCore

enum VyronSkillContextLoader {
    static func load(_ request: VyronSkillContextRequest) async throws -> VyronSkillRequestContext {
        try Task.checkCancellation()
        guard VyronSkillCommands.mightInvoke(in: request.prompt) || request.setup.permitsAutomaticSetup else {
            return .empty
        }
        let task = Task.detached(priority: .userInitiated) {
            let roots = request.setup.discoveryRoots(adding: request.roots)
            var inventory = try VyronSkillDiscovery().discover(in: roots)
            var commands = VyronSkillCommands(skills: inventory.skills)
            let setup = try await VyronAutomaticSkillSetup.prepare(
                request, commands: commands, discoveredSkills: inventory.skills
            )
            try Task.checkCancellation()
            if setup.didInstallSkills {
                inventory = try VyronSkillDiscovery().discover(in: roots)
                commands = VyronSkillCommands(skills: inventory.skills)
            }
            var selectionPrompt = request.prompt
            if let locations = request.setup.locations {
                for identifier in setup.identifiers {
                    guard let command = VyronAutomaticSkillSetup.managedCommand(
                        identifier: identifier, locations: locations, commands: commands
                    ) else { throw VyronSkillSetupError.failed }
                    selectionPrompt += "\n" + command.invocation
                }
            }
            let selected = commands.invoked(in: selectionPrompt)
            if selected.isEmpty, isLeadingSlashCommand(request.prompt) {
                throw VyronSkillContextError.unavailable
            }
            return try VyronSkillRequestContext(
                text: commands.context(for: selectionPrompt),
                commands: selected,
                catalog: commands.entries,
                didInstallSkills: setup.didInstallSkills
            )
        }
        return try await withTaskCancellationHandler {
            do {
                let result = try await task.value
                try Task.checkCancellation()
                return result
            } catch VyronSkillActivationError.truncatedDocument {
                throw VyronSkillContextError.documentTooLarge
            } catch is VyronSkillActivationError {
                throw VyronSkillContextError.unavailable
            }
        } onCancel: {
            task.cancel()
        }
    }

    private static func isLeadingSlashCommand(_ prompt: String) -> Bool {
        let token = prompt.split(whereSeparator: \.isWhitespace).first ?? ""
        guard token.first == "/", token.count > 1 else { return false }
        return token.dropFirst().allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || "-_.:".contains(character))
        }
    }
}
