import Foundation

extension DevelopmentAgent {
    static func recordTaskFailure(
        _ error: Error,
        progress: inout VyronDevelopmentRunProgress,
        onEvent: (DevelopmentEvent) -> Void
    ) {
        progress.state.finish(
            error is CancellationError || Task.isCancelled ? .stopped : .failed,
            detail: error.localizedDescription
        )
        do { try progress.save() }
        catch {
            onEvent(DevelopmentEvent(
                kind: .status, message: DevelopmentEvent.taskCheckpointUnavailableMessage,
                content: error.localizedDescription
            ))
        }
    }
}
