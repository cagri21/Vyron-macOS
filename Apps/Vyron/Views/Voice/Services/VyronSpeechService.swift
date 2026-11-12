import Foundation

@MainActor
protocol VyronSpeechService: AnyObject {
    var voices: [VyronVoiceOption] { get }

    func startListening(
        onUpdate: @escaping @MainActor (String, Bool) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) async throws
    func stopListening()
    func speak(_ text: String, voiceID: String, onFinished: @escaping @MainActor () -> Void)
    func stopSpeaking()
}
