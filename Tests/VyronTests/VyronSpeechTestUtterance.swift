@MainActor
struct VyronSpeechTestUtterance {
    let text: String
    let voiceID: String
    let onFinished: @MainActor () -> Void
}
