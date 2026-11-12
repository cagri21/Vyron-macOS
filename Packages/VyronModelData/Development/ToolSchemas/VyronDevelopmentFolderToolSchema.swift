import Foundation
import VyronModelDomain

enum VyronDevelopmentFolderToolSchema {
    private static let name = VyronDevelopmentToolName.createFolder
    private static let openName = VyronDevelopmentToolName.openProjectFolder

    private static let path = DevelopmentToolDefinition.Function.Parameters.Property(
        type: "string",
        description: "Project-relative, absolute, or ~/ folder path."
    )

    static let definition = DevelopmentToolDefinition(
        function: .init(
            name: name,
            description:
                "Create a folder needed for the current task and keep the conversation in its current project. "
                + "Call alone. Folder references in lookup requests require read-only tools.",
            parameters: .init(
                properties: [
                    "path": path,
                    "open_as_project": .init(
                        type: "boolean",
                        description: "Defaults to false. True requests a move to an existing folder only."
                    )
                ],
                required: ["path"]
            )
        )
    )

    static let openDefinition = DevelopmentToolDefinition(
        function: .init(
            name: openName,
            description: "Ask to move this conversation to an existing project folder at the user's request. "
                + "Call alone before edits or commands. Missing folders are never created.",
            parameters: .init(properties: ["path": path], required: ["path"])
        )
    )
}
