import Foundation

public struct VyronProjectFileOperationImpact: Codable, Sendable, Equatable {
    public let paths: VyronProjectFileOperationPaths
    public let affectedFilePaths: [String]
    public let isCaseSensitive: Bool

    private typealias CodingKeys = VyronProjectFileOperationImpactCodingKeys

    public init(
        paths: VyronProjectFileOperationPaths,
        affectedFilePaths: [String],
        isCaseSensitive: Bool = true
    ) {
        self.paths = paths
        self.affectedFilePaths = affectedFilePaths
        self.isCaseSensitive = isCaseSensitive
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paths = try container.decode(VyronProjectFileOperationPaths.self, forKey: .paths)
        affectedFilePaths = try container.decode([String].self, forKey: .affectedFilePaths)
        isCaseSensitive = try container.decodeIfPresent(Bool.self, forKey: .isCaseSensitive) ?? true
    }

    public func containsSource(_ path: String) -> Bool {
        let source = paths.sourcePath.split(separator: "/", omittingEmptySubsequences: false)
        let candidate = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !source.isEmpty, source.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
            candidate.count >= source.count,
            candidate.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        return zip(source, candidate).allSatisfy { expected, actual in
            isCaseSensitive ? expected == actual
                : String(expected).caseInsensitiveCompare(String(actual)) == .orderedSame
        }
    }

    public func relocatedPath(_ path: String) -> String? {
        guard containsSource(path), let destination = paths.destinationPath else { return nil }
        let sourceCount = paths.sourcePath.split(separator: "/").count
        let suffix = path.split(separator: "/").dropFirst(sourceCount).map(String.init)
        return ([destination] + suffix).joined(separator: "/")
    }
}
