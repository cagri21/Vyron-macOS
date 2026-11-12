import Combine
import Foundation
import VyronCore

@MainActor
final class VyronComposerSkillsModel: ObservableObject {
    @Published private(set) var query: String?
    @Published private(set) var selectedCommandID: String?
    @Published private(set) var isDismissed = false
    @Published private(set) var commands = VyronSkillCommands(skills: [])

    private let library: VyronSkillsPresentation
    private var libraryObservation: AnyCancellable?
    private var inventoryObservation: AnyCancellable?
    private var currentDraft = ""

    init(library: VyronSkillsPresentation = VyronSkillsPresentation()) {
        self.library = library
        libraryObservation = library.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        inventoryObservation = library.$inventory.sink { [weak self] inventory in
            self?.commands = VyronSkillCommands(skills: inventory?.skills ?? [])
        }
    }

    var inventory: VyronSkillInventory? { library.inventory }
    var isLoading: Bool { library.isLoading }
    var hasLoadError: Bool { library.hasLoadError }
    var refreshID: UUID { library.refreshID }
    var isPresented: Bool { query != nil && !isDismissed }

    var visibleCommands: [VyronComposerCommand] {
        guard let query else { return [] }
        let compact = VyronComposerCommand.compact
        let includesCompact = query.isEmpty || compact.name.localizedStandardContains(query)
            || compact.description.localizedStandardContains(query)
        return (includesCompact ? [compact] : []) + commands.matching(query: query).map(VyronComposerCommand.skill)
    }

    var selectedCommand: VyronComposerCommand? {
        let entries = visibleCommands
        return entries.first { $0.id == selectedCommandID } ?? entries.first
    }

    func load(projectDirectory: URL?) async {
        await library.load(projectDirectory: projectDirectory)
    }

    func refresh() {
        library.refresh()
    }

    func updateDraft(_ draft: String) {
        guard currentDraft != draft else { return }
        currentDraft = draft
        query = Self.query(in: draft)
        isDismissed = false
        selectedCommandID = nil
    }

    func dismiss() {
        isDismissed = true
    }

    func moveSelection(by offset: Int) {
        let entries = visibleCommands
        guard isPresented, !entries.isEmpty else { return }
        let selectedID = selectedCommand?.id
        let index = entries.firstIndex { $0.id == selectedID } ?? 0
        let nextIndex = min(max(index + offset, 0), entries.count - 1)
        selectedCommandID = entries[nextIndex].id
    }

    func replacement(for command: VyronComposerCommand, in draft: String) -> String? {
        guard isPresented, Self.query(in: draft) != nil,
            visibleCommands.contains(where: { $0.id == command.id })
        else { return nil }
        let leadingWhitespace = draft.prefix { $0.isWhitespace }
        return String(leadingWhitespace) + command.invocation + " "
    }

    static func query(in draft: String) -> String? {
        let token = draft.drop(while: { $0.isWhitespace })
        guard token.first == "/" else { return nil }
        let query = token.dropFirst()
        guard query.allSatisfy({ $0.isLetter || $0.isNumber || "-_:".contains($0) || $0 == "." }) else {
            return nil
        }
        return String(query)
    }
}
