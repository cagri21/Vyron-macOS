import Foundation
import VyronDevelopment

struct VyronDevelopmentFileOperationIntent: Codable, Sendable, Equatable {
    let id: UUID
    let identity: VyronDevelopmentIntegrationIdentity
    let paths: VyronProjectFileOperationPaths
    let disposition: VyronDevelopmentFileOperationDisposition

    func validate() throws {
        guard VyronDevelopmentFileOperationTools.names.contains(identity.toolName),
            identity.argumentsHash.count == 64,
            identity.argumentsHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw VyronDevelopmentTaskState.invalid("The saved file operation has an invalid tool identity.")
        }
        let kind: VyronProjectFileOperationKind = identity.toolName == VyronDevelopmentFileOperationTools.trash
            ? .trash : .move
        try VyronDevelopmentFileOperationEvidence(
            id: id, kind: kind, impact: .legacy(paths), recordedAt: Date(timeIntervalSince1970: 0)
        ).validate()
    }

    func finishing(_ disposition: VyronDevelopmentFileOperationDisposition) -> Self {
        Self(id: id, identity: identity, paths: paths, disposition: disposition)
    }
}
