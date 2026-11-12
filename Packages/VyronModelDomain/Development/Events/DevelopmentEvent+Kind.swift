extension DevelopmentEvent {
    public enum Kind: String, Codable, Sendable {
        case status, assistant, toolStarted, toolFinished, fileChanged, commandStarted, commandOutput, commandFinished
    }
}
