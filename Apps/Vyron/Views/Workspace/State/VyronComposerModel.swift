import Combine
import Foundation
import VyronModelDomain

@MainActor
final class VyronComposerModel: ObservableObject {
    @Published var draft = ""
    @Published var queueMessages: Bool {
        didSet { defaults.set(queueMessages, forKey: VyronUserDefaultsKey.queueFollowUpMessages.rawValue) }
    }
    @Published var editingQueuedMessageID: UUID?
    @Published var pendingSteeringIDs: Set<UUID> = []
    @Published var mode: ComposerMode = .agent {
        didSet {
            guard isModeCompatible(mode) else {
                mode = oldValue
                return
            }
            if mode != oldValue { didChangeMode() }
        }
    }
    @Published var effort: AgentEffort = .automatic

    var isModeCompatible: (ComposerMode) -> Bool = { _ in true }
    var didChangeMode: () -> Void = {}
    var queuedMessageDrainTask: Task<Void, Never>?

    private let defaults: UserDefaults
    private var draftBeforeQueueEdit = ""

    var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isEditingQueuedMessage: Bool { editingQueuedMessageID != nil }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        queueMessages = defaults.object(forKey: VyronUserDefaultsKey.queueFollowUpMessages.rawValue) as? Bool ?? true
    }

    func beginQueuedMessageEdit(_ message: VyronQueuedMessage) {
        cancelQueuedMessageDrain()
        draftBeforeQueueEdit = draft
        editingQueuedMessageID = message.id
        draft = message.content
    }

    func cancelQueuedMessageEdit() {
        guard isEditingQueuedMessage else { return }
        draft = draftBeforeQueueEdit
        draftBeforeQueueEdit = ""
        editingQueuedMessageID = nil
    }

    func cancelQueuedMessageDrain() {
        queuedMessageDrainTask?.cancel()
        queuedMessageDrainTask = nil
    }
}
