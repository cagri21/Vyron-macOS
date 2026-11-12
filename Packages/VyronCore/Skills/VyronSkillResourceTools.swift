import Foundation

/// Read-only text access is restricted to the skills explicitly selected for this turn.
public actor VyronSkillResourceTools {
    private var commands: [VyronSkillCommand]
    private var catalog: [VyronSkillCommand]

    public init(commands: [VyronSkillCommand], catalog: [VyronSkillCommand] = []) {
        self.commands = commands
        self.catalog = catalog + commands.filter { command in !catalog.contains(where: { $0.id == command.id }) }
    }

    public func include(_ selected: [VyronSkillCommand], catalog: [VyronSkillCommand] = []) {
        for command in catalog + selected {
            self.catalog.removeAll { $0.id == command.id }
            self.catalog.append(command)
        }
        for command in selected {
            commands.removeAll { $0.id == command.id || $0.name == command.name }
            commands.append(command)
        }
    }

    public nonisolated static let definitions: [DevelopmentExternalTool] = [
        DevelopmentExternalTool(
            name: "read_skill_resource",
            description: "Read a UTF-8 supporting file from a selected local skill. Supply its command name and relative path, such as references/development.md. A ../ companion path is allowed only when it exactly matches a local Markdown link in that skill's SKILL.md and targets another discovered skill. Reading a companion SKILL.md enables its returned command for later support reads. Read-only, no execution, no symbolic links, at most 64 KiB.",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "skill": .object(["type": .string("string")]),
                    "path": .object(["type": .string("string")])
                ]),
                "required": .array([.string("skill"), .string("path")]),
                "additionalProperties": .bool(false)
            ],
            isReadOnly: true
        )
    ]

    public nonisolated static func handles(_ call: DevelopmentToolCall) -> Bool {
        definitions.contains { $0.name == call.function.name }
    }

    public func execute(_ call: DevelopmentToolCall) async throws -> DevelopmentExternalResult {
        try Task.checkCancellation()
        guard Self.handles(call), Set(call.function.arguments.keys) == ["skill", "path"],
            case .string(let name) = call.function.arguments["skill"],
            case .string(let path) = call.function.arguments["path"],
            let command = commands.first(where: { $0.name == name })
        else { return Self.failure }
        do {
            if path.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
                return try readCompanion(path: path, from: command)
            }
            let text = try VyronSkillResourceReader().read(
                relativePath: path,
                directory: command.skill.fileURL.deletingLastPathComponent()
            )
            try Task.checkCancellation()
            return DevelopmentExternalResult(text: "Skill: \(command.invocation)\nResource: \(path)\n\n" + text)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return Self.failure
        }
    }

    private func readCompanion(path: String, from command: VyronSkillCommand) throws -> DevelopmentExternalResult {
        guard let reference = try VyronSkillCompanionReferences().resolve(path: path, from: command, catalog: catalog)
        else { return Self.failure }
        let text = try VyronSkillResourceReader().read(
            relativePath: reference.relativePath,
            directory: reference.command.skill.fileURL.deletingLastPathComponent()
        )
        try Task.checkCancellation()
        if reference.relativePath == "SKILL.md" { include([reference.command]) }
        return DevelopmentExternalResult(text:
            "Referenced skill: \(reference.command.invocation)\nResource: \(reference.relativePath)\n"
                + (reference.relativePath == "SKILL.md"
                    ? "Use skill=\"\(reference.command.name)\" for this companion's supporting files.\n" : "")
                + "\n" + text
        )
    }

    private nonisolated static var failure: DevelopmentExternalResult {
        DevelopmentExternalResult(
            text: "Skill resource could not be read. Use a selected skill command and a relative path to a regular UTF-8 text file inside its directory, at most 64 KiB. A ../ companion path must exactly match a local Markdown link in that skill's SKILL.md and target another discovered skill. Hidden paths, unreferenced traversal, symbolic links, and binary files are unavailable.",
            isError: true
        )
    }
}
