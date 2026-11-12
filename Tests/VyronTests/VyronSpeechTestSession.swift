import Foundation

@MainActor
final class VyronSpeechTestSession {
    let onUpdate: @MainActor (String, Bool) -> Void
    let onFailure: @MainActor (String) -> Void
    var permission: CheckedContinuation<Void, Never>?

    init(
        onUpdate: @escaping @MainActor (String, Bool) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        self.onUpdate = onUpdate
        self.onFailure = onFailure
    }
}
