import Foundation

/// URLSession invokes these framework callbacks across queues; the lock owns cancellation and task lifetime.
final class VyronConnectionBalanceTestURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = VyronConnectionBalanceTestState()

    private let lock = NSLock()
    private var loadingTask: Task<Void, Never>?
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let task = Task { @Sendable [self, request = self.request] in
            do {
                let fixture = try await Self.state.response(for: request)
                try Task.checkCancellation()
                guard let url = request.url,
                    let response = HTTPURLResponse(
                        url: url, statusCode: fixture.statusCode, httpVersion: "HTTP/1.1",
                        headerFields: fixture.headers
                    )
                else { throw URLError(.badURL) }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                var offset = 0
                while offset < fixture.body.count {
                    try Task.checkCancellation()
                    let end = min(offset + 257, fixture.body.count)
                    client?.urlProtocol(self, didLoad: fixture.body.subdata(in: offset..<end))
                    offset = end
                }
                if fixture.holdOpen { try await Task.sleep(for: .seconds(60)) }
                try Task.checkCancellation()
                client?.urlProtocolDidFinishLoading(self)
            } catch is CancellationError {
                // URLSession delivers cancellation to its awaiting client.
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        lock.withLock {
            loadingTask = task
            if stopped { task.cancel() }
        }
    }

    override func stopLoading() {
        lock.withLock {
            stopped = true
            loadingTask?.cancel()
        }
        Task { await Self.state.stopped() }
    }
}
