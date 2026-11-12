import Combine
import Foundation

@MainActor
final class VyronVoiceModel: ObservableObject {
    @Published private(set) var phase = VyronVoicePhase.idle
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLiveConversation = false
    @Published var selectedVoiceID: String {
        didSet { defaults.set(selectedVoiceID, forKey: VyronUserDefaultsKey.selectedSpeechVoiceID.rawValue) }
    }

    weak var conversation: (any VyronVoiceConversation)?
    var generationID: UUID?
    var isSendingTurn = false
    var draftPrefix = ""

    var voices: [VyronVoiceOption] { service.voices }
    var isActive: Bool { phase != .idle }

    private let service: any VyronSpeechService
    private let defaults: UserDefaults
    private let silenceDelay: Duration
    private var operationID = UUID()
    private var listeningTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var lastAttemptWasLive = false

    init(
        service: any VyronSpeechService,
        defaults: UserDefaults = .standard,
        silenceDelay: Duration = .milliseconds(1_500)
    ) {
        self.service = service
        self.defaults = defaults
        self.silenceDelay = silenceDelay
        let savedID = defaults.string(forKey: VyronUserDefaultsKey.selectedSpeechVoiceID.rawValue) ?? ""
        selectedVoiceID = savedID.isEmpty || service.voices.contains { $0.id == savedID } ? savedID : ""
    }

    func toggleDictation() {
        if isActive {
            end()
        } else {
            start(live: false)
        }
    }

    func toggleLiveConversation() {
        if isLiveConversation {
            end()
        } else {
            end()
            start(live: true)
        }
    }

    func end(cancelResponse: Bool = true) {
        let cancelTurn = isLiveConversation && phase == .thinking && cancelResponse
        operationID = UUID()
        listeningTask?.cancel()
        listeningTask = nil
        silenceTask?.cancel()
        silenceTask = nil
        service.stopListening()
        service.stopSpeaking()
        isLiveConversation = false
        phase = .idle
        if cancelTurn { conversation?.cancelVoiceTurn() }
    }

    func interrupt() {
        guard isLiveConversation, phase == .speaking || phase == .thinking else { return }
        let cancelTurn = phase == .thinking
        // Change state before cancellation so the app's stop hook cannot end this session.
        phase = .idle
        operationID = UUID()
        service.stopSpeaking()
        if cancelTurn { conversation?.cancelVoiceTurn() }
        isLiveConversation = true
        beginListening()
    }

    func responseFinished(answer: String?, error: String?) {
        guard isLiveConversation, phase == .thinking else { return }
        if let error {
            fail(error)
            return
        }
        guard let answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            beginListening()
            return
        }
        phase = .speaking
        let id = operationID
        service.speak(answer, voiceID: selectedVoiceID) { [weak self] in
            guard let self, self.operationID == id, self.isLiveConversation, self.phase == .speaking else { return }
            self.beginListening()
        }
    }

    func previewVoice() {
        guard !isLiveConversation, phase == .idle || phase == .speaking else { return }
        end()
        errorMessage = nil
        phase = .speaking
        let id = operationID
        service.speak(VyronVoiceText.previewPhrase, voiceID: selectedVoiceID) { [weak self] in
            guard let self, self.operationID == id else { return }
            self.phase = .idle
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func retryLastSession() {
        guard !isActive else { return }
        start(live: lastAttemptWasLive)
    }

    private func start(live: Bool) {
        lastAttemptWasLive = live
        errorMessage = nil
        transcript = ""
        guard let conversation else {
            fail(VyronVoiceText.busy)
            return
        }
        if let error = conversation.validateVoiceStart(live: live) {
            fail(error)
            return
        }
        isLiveConversation = live
        beginListening()
    }

    private func beginListening() {
        operationID = UUID()
        let id = operationID
        transcript = ""
        phase = .requestingPermission
        silenceTask?.cancel()
        listeningTask?.cancel()
        listeningTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.startListening(
                    onUpdate: { [weak self] text, final in
                        self?.receive(text, final: final, operation: id)
                    },
                    onFailure: { [weak self] error in
                        guard let self, self.operationID == id else { return }
                        self.fail(error)
                    }
                )
                guard !Task.isCancelled, operationID == id else { return }
                if phase == .requestingPermission { phase = .listening }
            } catch is CancellationError {
                // Ending or replacing a session intentionally cancels permission/start work.
            } catch {
                guard !Task.isCancelled, operationID == id else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func receive(_ text: String, final: Bool, operation: UUID) {
        guard operationID == operation, phase == .listening || phase == .requestingPermission else { return }
        let changed = transcript != text
        phase = .listening
        transcript = text
        if !isLiveConversation {
            conversation?.updateVoiceDraft(text)
            if final { end() }
            return
        }
        guard changed || final else { return }
        silenceTask?.cancel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if final { beginListening() }
            return
        }
        if final {
            submitTurn()
        } else {
            silenceTask = Task { [weak self, silenceDelay] in
                do {
                    try await Task.sleep(for: silenceDelay)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled, self.operationID == operation,
                    self.phase == .listening else { return }
                self.submitTurn()
            }
        }
    }

    private func submitTurn() {
        let prompt = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        operationID = UUID()
        silenceTask?.cancel()
        silenceTask = nil
        service.stopListening()
        phase = .thinking
        guard conversation?.sendVoiceTurn(prompt) == true else {
            fail(VyronVoiceText.busy)
            return
        }
    }

    private func fail(_ message: String) {
        end(cancelResponse: false)
        errorMessage = message
    }
}
