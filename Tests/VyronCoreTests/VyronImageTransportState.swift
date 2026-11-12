import Foundation

final class VyronImageTransportState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (Int, String))?

    func set(_ handler: (@Sendable (URLRequest) throws -> (Int, String))?) {
        lock.withLock { self.handler = handler }
    }

    func response(for request: URLRequest) throws -> (Int, String) {
        guard let action = lock.withLock({ handler }) else { throw URLError(.unsupportedURL) }
        return try action(request)
    }
}
