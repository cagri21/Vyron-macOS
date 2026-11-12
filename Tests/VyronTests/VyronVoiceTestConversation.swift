@testable import Vyron

@MainActor
final class VyronVoiceTestConversation: VyronVoiceConversation {
    var validationError: String?
    var acceptsTurns = true
    var drafts: [String] = []
    var turns: [String] = []
    var cancellations = 0
    var onCancel: (@MainActor () -> Void)?

    func validateVoiceStart(live: Bool) -> String? { validationError }

    func updateVoiceDraft(_ transcript: String) {
        drafts.append(transcript)
    }

    func sendVoiceTurn(_ transcript: String) -> Bool {
        turns.append(transcript)
        return acceptsTurns
    }

    func cancelVoiceTurn() {
        cancellations += 1
        onCancel?()
    }
}
