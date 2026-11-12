import Foundation

/// URLSession streams deliver tokens through a Sendable callback; all storage is protected by this lock.
final class VyronThinkingTokenRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    var tokens: [String] { lock.withLock { values } }

    func record(_ token: String) {
        lock.withLock { values.append(token) }
    }
}
