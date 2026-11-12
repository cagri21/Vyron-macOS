import Foundation

/// Keeps synchronous macOS Keychain calls off the presentation actor during app startup.
public actor VyronModelCredentialReader {
    private let store: ModelCredentialStore

    public init(store: ModelCredentialStore) {
        self.store = store
    }

    public func key(for id: UUID) throws -> String {
        try Task.checkCancellation()
        return try store.key(for: id)
    }
}
