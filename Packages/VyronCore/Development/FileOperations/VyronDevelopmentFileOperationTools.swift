import Foundation
import VyronDevelopment

enum VyronDevelopmentFileOperationTools {
    static let move = "move_item"
    static let rename = "rename_item"
    static let trash = "trash_item"
    static let names: Set<String> = [move, rename, trash]

    static let definitions: [DevelopmentExternalTool] = [
        definition(move, description: "Move a project file or folder; never overwrite.", properties: [
            "source": "Relative source path.",
            "destination": "Exact relative destination path."
        ]),
        definition(rename, description: "Rename a project file or folder; never overwrite.", properties: [
            "path": "Relative source path.",
            "new_name": "New filename, without a directory."
        ]),
        definition(trash, description: "Move a project file or folder to Trash, never permanently delete.", properties: [
            "path": "Relative source path."
        ])
    ]

    static func handles(_ call: DevelopmentToolCall) -> Bool {
        names.contains(call.function.name)
    }

    static func decode(_ call: DevelopmentToolCall) throws -> VyronProjectFileOperationRequest {
        let arguments = call.function.arguments
        switch call.function.name {
        case move:
            try requireKeys(arguments, expected: ["source", "destination"])
            return .move(VyronProjectFileMoveRequest(
                sourcePath: try path(arguments, key: "source"),
                destinationPath: try path(arguments, key: "destination")
            ))
        case rename:
            try requireKeys(arguments, expected: ["path", "new_name"])
            let name = try path(arguments, key: "new_name")
            guard !name.contains("/"), name.utf8.count <= 255 else {
                throw invalid("new_name must be one filename under 256 bytes.")
            }
            return .rename(VyronProjectFileRenameRequest(path: try path(arguments, key: "path"), newName: name))
        case trash:
            try requireKeys(arguments, expected: ["path"])
            return .trash(VyronProjectFileTrashRequest(path: try path(arguments, key: "path")))
        default:
            throw invalid("This project file operation is unavailable.")
        }
    }

    private static func definition(
        _ name: String,
        description: String,
        properties: [String: String]
    ) -> DevelopmentExternalTool {
        DevelopmentExternalTool(
            name: name, description: description,
            inputSchema: [
                "type": .string("object"),
                "properties": .object(properties.mapValues { description in
                    .object(["type": .string("string"), "description": .string(description)])
                }),
                "required": .array(properties.keys.sorted().map(DevelopmentJSONValue.string)),
                "additionalProperties": .bool(false)
            ],
            isReadOnly: false
        )
    }

    private static func requireKeys(_ arguments: [String: DevelopmentJSONValue], expected: Set<String>) throws {
        guard Set(arguments.keys) == expected else {
            throw invalid("Provide exactly the required project file operation arguments.")
        }
    }

    private static func path(_ arguments: [String: DevelopmentJSONValue], key: String) throws -> String {
        guard case .string(let path) = arguments[key], !path.isEmpty, path.utf8.count <= 4_096,
            !path.hasPrefix("/"), !path.hasPrefix("~"),
            path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw invalid("Use a bounded relative project path without control characters.")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else {
            throw invalid("Project paths cannot contain traversal or empty components.")
        }
        return path
    }

    private static func invalid(_ message: String) -> DevelopmentAgentError {
        .invalidTool(message)
    }
}
