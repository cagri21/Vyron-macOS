import Foundation

/// URLSession calls the fixture from its own queue; the lock owns all mutable state.
final class VyronCompatibleFeatureTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> String)?
    private var count = 0

    var requestCount: Int { lock.withLock { count } }

    func reset(_ handler: (@Sendable (URLRequest) throws -> String)? = nil) {
        lock.withLock {
            self.handler = handler
            count = 0
        }
    }

    func body(for request: URLRequest) throws -> String {
        let handler = lock.withLock {
            count += 1
            return self.handler
        }
        guard let handler else { throw URLError(.unsupportedURL) }
        return try handler(request)
    }
}
