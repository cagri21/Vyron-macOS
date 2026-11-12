import Foundation

public struct VyronProjectFileOperationResult: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: VyronProjectFileOperationKind
    public let impact: VyronProjectFileOperationImpact
    public let recoveryURL: URL?

    public var paths: VyronProjectFileOperationPaths { impact.paths }
    public var sourcePath: String { paths.sourcePath }
    public var destinationPath: String? { paths.destinationPath }
    public var affectedFilePaths: [String] { impact.affectedFilePaths }
}
