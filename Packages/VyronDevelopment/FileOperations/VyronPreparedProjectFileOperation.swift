import Foundation

public struct VyronPreparedProjectFileOperation: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let request: VyronProjectFileOperationRequest
    let snapshot: VyronProjectFileSnapshot
    let preparedAt: Date

    public var sourcePath: String { request.paths.sourcePath }
    public var destinationPath: String? { request.paths.destinationPath }
    public var kind: VyronProjectFileOperationKind { request.kind }
    public var isCaseSensitive: Bool { snapshot.isCaseSensitive }
    public var impact: VyronProjectFileOperationImpact {
        VyronProjectFileOperationImpact(
            paths: request.paths, affectedFilePaths: affectedFilePaths, isCaseSensitive: isCaseSensitive
        )
    }
    public var affectedFilePaths: [String] {
        snapshot.entries.filter { !$0.isDirectory }.flatMap { entry in
            let suffix = entry.relativePath.isEmpty ? "" : "/" + entry.relativePath
            return [sourcePath + suffix] + (destinationPath.map { [$0 + suffix] } ?? [])
        }
    }
}
