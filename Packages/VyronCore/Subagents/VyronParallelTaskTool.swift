import Foundation

enum VyronParallelTaskTool {
    static let name = VyronDevelopmentToolName.parallelTasks

    static let definition = DevelopmentExternalTool(
        name: name,
        description: "Delegate one to three independent, focused project research or review tasks to parallel read-only subagents using the same selected model. Subagents can inspect source, but cannot edit, run commands, use integrations, ask the user, or delegate further. You must integrate their findings. Use only when independent work materially helps; at most three helpers per parent task.",
        inputSchema: [
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("tasks")]),
            "properties": .object([
                "tasks": .object([
                    "type": .string("array"),
                    "minItems": .number(1),
                    "maxItems": .number(3),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "required": .array([.string("name"), .string("prompt")]),
                        "properties": .object([
                            "name": .object([
                                "type": .string("string"),
                                "description": .string("A unique short task name, at most 80 UTF-8 bytes."),
                                "minLength": .number(1),
                                "maxLength": .number(80)
                            ]),
                            "prompt": .object([
                                "type": .string("string"),
                                "description": .string("The focused question to investigate, at most 2,000 characters and 6,000 UTF-8 bytes. Include needed context and a concrete expected result."),
                                "minLength": .number(1),
                                "maxLength": .number(2_000)
                            ])
                        ])
                    ])
                ])
            ])
        ],
        isReadOnly: true
    )

    static func decode(_ call: DevelopmentToolCall) throws -> [VyronParallelTask] {
        guard call.function.name == name,
            Set(call.function.arguments.keys) == ["tasks"],
            case .array(let values) = call.function.arguments["tasks"],
            (1...VyronParallelTaskLimits.maximumTasks).contains(values.count)
        else { throw invalidRequest() }
        let tasks = try values.map { value in
            guard case .object(let fields) = value,
                Set(fields.keys) == ["name", "prompt"],
                case .string(let rawName) = fields["name"],
                case .string(let rawPrompt) = fields["prompt"]
            else { throw invalidRequest() }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !prompt.isEmpty,
                name.utf8.count <= VyronParallelTaskLimits.maximumNameBytes,
                prompt.count <= VyronParallelTaskLimits.maximumPromptCharacters,
                prompt.utf8.count <= VyronParallelTaskLimits.maximumPromptBytes,
                !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                !prompt.unicodeScalars.contains(where: { $0.value == 0 })
            else { throw invalidRequest() }
            return VyronParallelTask(name: name, prompt: prompt)
        }
        guard Set(tasks.map { $0.name.lowercased() }).count == tasks.count else { throw invalidRequest() }
        return tasks
    }

    private static func invalidRequest() -> DevelopmentAgentError {
        .invalidTool("Provide one to three distinct named read-only tasks with bounded, nonempty prompts.")
    }
}
