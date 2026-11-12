import Foundation

struct VyronDevelopmentCheckpointFailure: Error, LocalizedError {
    let detail: String

    var errorDescription: String? {
        "Completed actions must not be repeated. Task progress could not be saved: \(detail)"
    }
}
