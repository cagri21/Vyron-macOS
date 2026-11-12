import Foundation
import VyronDevelopment

struct VyronDevelopmentFileOperationEvidence: Codable, Sendable, Equatable {
    let id: UUID
    let kind: VyronProjectFileOperationKind
    let impact: VyronDevelopmentFileOperationImpact
    let recordedAt: Date

    var paths: VyronProjectFileOperationPaths {
        switch impact {
        case .complete(let value): value.paths
        case .legacy(let value): value
        }
    }

    var affectedFilePaths: [String] {
        guard case .complete(let value) = impact else { return [] }
        return value.affectedFilePaths
    }

    var hasCompleteImpact: Bool {
        if case .complete = impact { return true }
        return false
    }

    func containsSource(_ path: String) -> Bool {
        switch impact {
        case .complete(let value): value.containsSource(path)
        case .legacy(let value): path == value.sourcePath || path.hasPrefix(value.sourcePath + "/")
        }
    }

    func relocatedPath(_ path: String) -> String? {
        switch impact {
        case .complete(let value): value.relocatedPath(path)
        case .legacy(let value):
            value.destinationPath.map { $0 + String(path.dropFirst(value.sourcePath.count)) }
        }
    }

    init(
        id: UUID,
        kind: VyronProjectFileOperationKind,
        impact: VyronDevelopmentFileOperationImpact,
        recordedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.impact = impact
        self.recordedAt = recordedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(VyronProjectFileOperationKind.self, forKey: .kind)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        if let value = try values.decodeIfPresent(VyronProjectFileOperationImpact.self, forKey: .impact) {
            impact = .complete(value)
        } else {
            impact = .legacy(try values.decode(VyronProjectFileOperationPaths.self, forKey: .paths))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(recordedAt, forKey: .recordedAt)
        switch impact {
        case .complete(let value): try values.encode(value, forKey: .impact)
        case .legacy(let value): try values.encode(value, forKey: .paths)
        }
    }

    func validate() throws {
        try Self.validatePath(paths.sourcePath)
        try affectedFilePaths.forEach(Self.validatePath)
        guard recordedAt.timeIntervalSince1970.isFinite else {
            throw VyronDevelopmentTaskState.invalid("The file operation has an invalid recording time.")
        }
        switch kind {
        case .move, .rename:
            guard let destination = paths.destinationPath else {
                throw VyronDevelopmentTaskState.invalid("A saved move or rename needs its destination path.")
            }
            try Self.validatePath(destination)
            guard destination != paths.sourcePath,
                !destination.hasPrefix(paths.sourcePath + "/") else {
                throw VyronDevelopmentTaskState.invalid("A saved move cannot place an item inside itself.")
            }
        case .trash:
            guard paths.destinationPath == nil else {
                throw VyronDevelopmentTaskState.invalid("A saved Trash action cannot target another project path.")
            }
        }
    }

    private static func validatePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard VyronDevelopmentTaskText.isValid(path, maximumBytes: 4_096), !path.hasPrefix("/"),
            !path.hasPrefix("~"), components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw VyronDevelopmentTaskState.invalid("A saved file operation has an unsafe project path.")
        }
    }
}
