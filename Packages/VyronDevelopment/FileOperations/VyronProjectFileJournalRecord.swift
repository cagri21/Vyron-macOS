import Foundation

struct VyronProjectFileJournalRecord: Codable, Sendable {
    let identity: VyronProjectFileJournalIdentity
    var state: VyronProjectFileJournalState
    let archivedChanges: [DevelopmentChange]

    var phase: VyronProjectFileOperationPhase {
        get { state.phase }
        set { state.phase = newValue }
    }

    var result: VyronProjectFileOperationResult? {
        get { state.result }
        set { state.result = newValue }
    }

    init(
        identity: VyronProjectFileJournalIdentity,
        phase: VyronProjectFileOperationPhase,
        result: VyronProjectFileOperationResult?,
        archivedChanges: [DevelopmentChange]
    ) {
        self.identity = identity
        state = VyronProjectFileJournalState(phase: phase, result: result, updatedAt: Date(), stagedURL: nil)
        self.archivedChanges = archivedChanges
    }
}
