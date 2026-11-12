import Foundation
@testable import Vyron

@MainActor
final class VyronSpeechTestService: VyronSpeechService {
    let voices = [
        VyronVoiceOption(id: "voice-a", name: "Voice A", language: "en-US"),
        VyronVoiceOption(id: "voice-b", name: "Voice B", language: "tr-TR")
    ]
    var sessions: [VyronSpeechTestSession] = []
    var utterances: [VyronSpeechTestUtterance] = []
    var suspendPermission = false
    private(set) var listeningStops = 0
    private(set) var speakingStops = 0

    func startListening(
        onUpdate: @escaping @MainActor (String, Bool) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) async throws {
        let session = VyronSpeechTestSession(onUpdate: onUpdate, onFailure: onFailure)
        sessions.append(session)
        if suspendPermission {
            await withCheckedContinuation { session.permission = $0 }
        }
        try Task.checkCancellation()
    }

    func stopListening() {
        listeningStops += 1
    }

    func speak(_ text: String, voiceID: String, onFinished: @escaping @MainActor () -> Void) {
        utterances.append(VyronSpeechTestUtterance(text: text, voiceID: voiceID, onFinished: onFinished))
    }

    func stopSpeaking() {
        speakingStops += 1
    }

    func grantPermission(_ index: Int) {
        sessions[index].permission?.resume()
        sessions[index].permission = nil
    }
}
