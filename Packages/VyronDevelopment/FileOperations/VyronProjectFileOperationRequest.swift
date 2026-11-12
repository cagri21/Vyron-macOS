import Foundation

public enum VyronProjectFileOperationRequest: Codable, Sendable, Equatable {
    case move(VyronProjectFileMoveRequest)
    case rename(VyronProjectFileRenameRequest)
    case trash(VyronProjectFileTrashRequest)

    public var kind: VyronProjectFileOperationKind {
        switch self {
        case .move: .move
        case .rename: .rename
        case .trash: .trash
        }
    }

    public var paths: VyronProjectFileOperationPaths {
        switch self {
        case .move(let request):
            VyronProjectFileOperationPaths(sourcePath: request.sourcePath, destinationPath: request.destinationPath)
        case .rename(let request):
            VyronProjectFileOperationPaths(
                sourcePath: request.path,
                destinationPath: Self.parentPath(request.path, name: request.newName)
            )
        case .trash(let request):
            VyronProjectFileOperationPaths(sourcePath: request.path, destinationPath: nil)
        }
    }

    static func parentPath(_ path: String, name: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? name : parent + "/" + name
    }
}
