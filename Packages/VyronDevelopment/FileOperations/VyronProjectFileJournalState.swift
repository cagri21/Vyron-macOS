import Foundation

struct VyronProjectFileJournalState: Codable, Sendable {
    var phase: VyronProjectFileOperationPhase
    var result: VyronProjectFileOperationResult?
    var updatedAt: Date
    var stagedURL: URL?
}
