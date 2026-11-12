import Combine
import Foundation
import VyronDevelopment
import VyronModelDomain

@MainActor
final class VyronWorkspaceInspectorState: ObservableObject {
    @Published var developmentFiles: [DevelopmentFile] = []
    @Published var developmentChanges: [DevelopmentChange] = []
    @Published private var recordedEvents: [DevelopmentEvent] = []
    @Published private var outputConversationID: UUID?
    @Published private var displayedConversationID: UUID?
    @Published var inspectorTab: ProjectInspectorTab = .files
    @Published var selectedProjectFilePath: String?
    @Published var projectFilePreview = ""
    @Published var selectedChangePath: String?
    @Published private var recordedTerminalOutput = ""
    @Published var showTerminal = false

    var projectPreviewID = UUID()

    private var showsDevelopmentOutput: Bool { outputConversationID == displayedConversationID }

    var developmentEvents: [DevelopmentEvent] { showsDevelopmentOutput ? recordedEvents : [] }

    var terminalOutput: String {
        get { showsDevelopmentOutput ? recordedTerminalOutput : "" }
        set {
            if showsDevelopmentOutput { recordedTerminalOutput = newValue }
        }
    }

    func showDevelopmentOutput(for conversationID: UUID?) {
        displayedConversationID = conversationID
    }

    func beginDevelopmentOutput(for conversationID: UUID, selectedConversationID: UUID?) {
        outputConversationID = conversationID
        displayedConversationID = selectedConversationID
        recordedEvents = []
        recordedTerminalOutput = ""
    }

    var selectedDevelopmentChange: DevelopmentChange? {
        developmentChanges.first { $0.path == selectedChangePath } ?? developmentChanges.first
    }

    func filteredDevelopmentFiles(matching searchText: String) -> [DevelopmentFile] {
        guard !searchText.isEmpty else { return developmentFiles }
        return developmentFiles.filter { $0.path.localizedCaseInsensitiveContains(searchText) }
    }

    func record(_ event: DevelopmentEvent) {
        if event.kind != .commandOutput {
            recordedEvents.append(event)
            let overflow = recordedEvents.count - VyronWorkspaceInspectorLimits.maximumEvents
            if overflow > 0 { recordedEvents.removeFirst(overflow) }
        }
        switch event.kind {
        case .commandStarted:
            recordedTerminalOutput += "\n$ \(event.command ?? event.localizedMessage)\n"
        case .commandOutput:
            recordedTerminalOutput += event.content ?? ""
        case .commandFinished:
            recordedTerminalOutput += "\n[\(event.localizedMessage)]\n"
        default:
            break
        }
    }

    func recordCompletedCommands(_ commands: [CommandResult]) {
        guard !commands.isEmpty else { return }
        let newline = VyronTextSeparator.line.rawValue
        recordedTerminalOutput = commands.map { command in
            let status = command.timedOut ? "timed out" : "exit \(command.exitCode)"
            return ["$ \(command.command)", command.output, "[\(status)]", ""].joined(separator: newline)
        }.joined(separator: newline)
    }

    func trimTerminalOutput() {
        guard recordedTerminalOutput.utf8.count > VyronWorkspaceInspectorLimits.maximumTerminalOutputBytes else { return }
        recordedTerminalOutput =
            "[Earlier terminal output omitted]\n"
            + String(recordedTerminalOutput.suffix(VyronWorkspaceInspectorLimits.retainedTerminalOutputCharacters))
    }
}
