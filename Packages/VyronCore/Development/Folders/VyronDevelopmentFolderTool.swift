import Foundation
import VyronDevelopment
import VyronModelDomain

enum VyronDevelopmentFolderTool {
    static let name = VyronDevelopmentToolName.createFolder
    static let openName = VyronDevelopmentToolName.openProjectFolder
    static let names: Set<String> = [name, openName]

    static func decode(_ call: DevelopmentToolCall, projectURL: URL) throws -> VyronDevelopmentFolderRequest {
        let arguments = call.function.arguments
        let opensExistingFolder = call.function.name == openName
        let allowedArguments: Set<String> = opensExistingFolder ? ["path"] : ["path", "open_as_project"]
        guard Set(arguments.keys).isSubset(of: allowedArguments),
            case .string(let requestedPath) = arguments["path"],
            !requestedPath.isEmpty, requestedPath.utf8.count <= 4_096, !requestedPath.contains("\0") else {
            throw DevelopmentAgentError.invalidTool("Provide a valid folder path using the tool's supported arguments.")
        }
        let explicitOpening: Bool?
        if let value = arguments["open_as_project"] {
            guard case .bool(let enabled) = value else {
                throw DevelopmentAgentError.invalidTool("open_as_project must be a boolean.")
            }
            explicitOpening = enabled
        } else {
            explicitOpening = nil
        }
        var path = requestedPath
        if explicitOpening != false, !path.hasPrefix("~"), !path.contains("/"),
            path.caseInsensitiveCompare(projectURL.lastPathComponent) == .orderedSame {
            let candidate = projectURL.deletingLastPathComponent().appendingPathComponent(path, isDirectory: true)
            let validatedCandidate = try VyronFolderCreation.destination(for: VyronFolderCreationRequest(
                path: candidate.path, projectURL: projectURL
            ))
            if try VyronFolderCreation.matchesProjectRoot(validatedCandidate, projectURL: projectURL) {
                path = projectURL.path
            }
        }
        return VyronDevelopmentFolderRequest(path: path, openAsProject: opensExistingFolder || explicitOpening == true)
    }
}
