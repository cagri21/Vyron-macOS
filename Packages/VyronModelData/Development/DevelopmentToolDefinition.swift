import Foundation
import VyronLocalization
import VyronModelDomain

struct DevelopmentToolDefinition: Encodable {
    let type = "function"
    let function: Function

    static func available(
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) throws -> [DevelopmentToolDefinition] {
        let builtins =
            mode == .plan
            ? all.filter {
                [
                    "list_files", "read_file", "search", VyronUserInputToolName.value,
                    VyronDevelopmentPlanToolSchema.name,
                    VyronDevelopmentResumeToolSchema.name
                ].contains($0.function.name)
            }
            : all
        let extras = externalTools.filter { mode != .plan || $0.isReadOnly }
        let names = builtins.map { $0.function.name } + extras.map(\.name)
        guard extras.count <= 64, Set(names).count == names.count,
            extras.allSatisfy({
                $0.name.range(of: "^[a-zA-Z0-9_-]{1,64}$", options: .regularExpression) != nil
                    && $0.inputSchema["type"] == .string("object")
            }),
            try JSONEncoder().encode(extras.map(\.inputSchema)).count <= 48_000
        else {
            throw DevelopmentAgentError.invalidTool(
                VyronModelDataText.invalidToolCatalog
            )
        }
        return builtins
            + extras.map {
                .init(
                    function: .init(
                        name: $0.name,
                        description: $0.description,
                        parameters: .init(schema: $0.inputSchema)
                    )
                )
            }
    }

    static let all: [DevelopmentToolDefinition] = [
        make(
            "list_files",
            "List source files inside the selected project.",
            ["limit": ("integer", "Maximum files, 1 to 300.")],
            []
        ),
        make(
            "read_file",
            "Read a bounded excerpt of a project file before editing. Truncation is explicit.",
            ["path": ("string", "Project-relative file path.")],
            ["path"]
        ),
        make(
            "search",
            "Search source text inside the project.",
            ["query": ("string", "Literal text to find."), "limit": ("integer", "Maximum matches, 1 to 60.")],
            ["query"]
        ),
        make(
            "edit_file",
            "Replace one unique exact observed text fragment in a previously read file; preserves all other content.",
            [
                "path": ("string", "Project-relative path."),
                "old_text": ("string", "Exact unique text already read from this file."),
                "new_text": ("string", "Replacement text.")
            ],
            ["path", "old_text", "new_text"]
        ),
        make(
            "write_file",
            "Create a new file or replace a fully read existing file. Never replace truncated content.",
            ["path": ("string", "Project-relative path."), "content": ("string", "Complete file content.")],
            ["path", "content"]
        ),
        make(
            "run_command",
            "Run a local project command under native command policy. May require user review. No networking or shell wrappers.",
            [
                "command": ("string", "Command and arguments, for example swift test."),
                "timeout_seconds": ("integer", "Timeout from 5 to 180 seconds, default 120.")
            ],
            ["command"]
        ),
        VyronDevelopmentFolderToolSchema.definition,
        VyronDevelopmentFolderToolSchema.openDefinition,
        userInput,
        plan,
        resume
    ]

    private static func make(
        _ name: String,
        _ description: String,
        _ properties: [String: (String, String)],
        _ required: [String]
    ) -> DevelopmentToolDefinition {
        DevelopmentToolDefinition(
            function: Function(
                name: name,
                description: description,
                parameters: .init(
                    properties: properties.mapValues { .init(type: $0.0, description: $0.1) },
                    required: required
                )
            )
        )
    }
}
