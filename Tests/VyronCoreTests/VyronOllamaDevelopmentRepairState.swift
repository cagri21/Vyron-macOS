import Foundation

/// URLProtocol callbacks are concurrent; the lock protects every stored fixture value.
final class VyronOllamaDevelopmentRepairState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Int, Data) throws -> Data)?
    private var bodies: [Data] = []
    private var status = 200

    func configure(status: Int = 200, handler: @escaping @Sendable (Int, Data) throws -> Data) {
        lock.withLock {
            self.status = status
            self.handler = handler
            bodies = []
        }
    }

    func reset() {
        lock.withLock {
            handler = nil
            bodies = []
            status = 200
        }
    }

    var requests: [Data] { lock.withLock { bodies } }
    var responseStatus: Int { lock.withLock { status } }

    func response(to body: Data) throws -> Data {
        let count = lock.withLock {
            bodies.append(body)
            return bodies.count
        }
        guard let handler = lock.withLock({ handler }) else { throw URLError(.unsupportedURL) }
        return try handler(count, body)
    }
}
