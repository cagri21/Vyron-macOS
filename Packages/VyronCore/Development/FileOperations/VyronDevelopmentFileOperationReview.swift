import Foundation
import VyronDevelopment

enum VyronDevelopmentFileOperationReview {
    static func identity(for prepared: VyronPreparedProjectFileOperation) -> DevelopmentToolCall {
        let caseSensitive = prepared.isCaseSensitive
        func normalized(_ path: String) -> String {
            let canonical = path.precomposedStringWithCanonicalMapping
            return caseSensitive ? canonical : canonical.lowercased()
        }
        if let destination = prepared.destinationPath {
            return DevelopmentToolCall(name: VyronDevelopmentFileOperationTools.move, arguments: [
                "source": .string(normalized(prepared.sourcePath)),
                "destination": .string(normalized(destination))
            ])
        }
        return DevelopmentToolCall(name: VyronDevelopmentFileOperationTools.trash, arguments: [
            "path": .string(normalized(prepared.sourcePath))
        ])
    }

    static func approval(
        for prepared: VyronPreparedProjectFileOperation,
        projectURL: URL
    ) -> CommandApproval {
        let action: VyronDevelopmentApprovalAction
        switch prepared.request {
        case .move: action = .moveProjectItem
        case .rename: action = .renameProjectItem
        case .trash: action = .trashProjectItem
        }
        let source = projectURL.appendingPathComponent(prepared.sourcePath).path
        let detail = prepared.destinationPath.map {
            source + "\n→ " + projectURL.appendingPathComponent($0).path
        } ?? source
        return CommandApproval(
            command: detail,
            reason: "Review this project file operation before changing the filesystem.",
            action: action
        )
    }
}
