extension DevelopmentEvent {
    public static let taskCheckpointUnavailableMessage = "Task progress could not be saved"

    public var isTaskCheckpointFailure: Bool {
        kind == .status && message == Self.taskCheckpointUnavailableMessage
    }
}
