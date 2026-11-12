@MainActor
protocol VyronVoiceConversation: AnyObject {
    func validateVoiceStart(live: Bool) -> String?
    func updateVoiceDraft(_ transcript: String)
    func sendVoiceTurn(_ transcript: String) -> Bool
    func cancelVoiceTurn()
}
