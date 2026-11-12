import Foundation

/// URLProtocol callbacks use different queues; the lock protects the handler and captured requests.
final class VyronDevelopmentBudgetTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> Data)?
    private var capturedRequests: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { capturedRequests } }

    func configure(_ handler: (@Sendable (URLRequest) throws -> Data)?) {
        lock.withLock {
            self.handler = handler
            capturedRequests = []
        }
    }

    func response(for request: URLRequest) throws -> Data {
        let handler = lock.withLock {
            capturedRequests.append(request)
            return self.handler
        }
        guard let handler else { throw URLError(.unsupportedURL) }
        return try handler(request)
    }
}
