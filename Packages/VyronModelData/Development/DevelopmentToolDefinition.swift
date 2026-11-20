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
            "List project paths, with implementation files first. Filter filenames/paths with query; continue using next_offset. Contents are not searched.",
            [
                "limit": ("integer", "Maximum files per page, 1 to 300, default 100."),
                "offset": ("integer", "Inventory offset, default 0. Use next_offset from the previous result."),
                "query": ("string", "Optional literal filename/path substring, for example .py or examples/.")
            ],
            []
        ),
        make(
            "read_file",
            "Read a bounded UTF-8 file page. Use next_offset to read later ranges. Partial reads never authorize whole-file replacement.",
            [
                "path": ("string", "Project-relative file path."),
                "offset": ("integer", "UTF-8 byte offset, default 0. Use next_offset from the previous result.")
            ],
            ["path"]
        ),
        make(
            "search",
            "Search literal file contents inside the project. For filenames or paths, use list_files with query instead.",
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
