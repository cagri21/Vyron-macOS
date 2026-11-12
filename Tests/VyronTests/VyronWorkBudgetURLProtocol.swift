import Foundation

/// URLSession callbacks cross queues; the lock protects this fixture's task lifetime.
final class VyronWorkBudgetURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = VyronWorkBudgetTransportState()

    private let lock = NSLock()
    private var loadingTask: Task<Void, Never>?
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let task = Task {
            do {
                let data = try await Self.state.response(for: request)
                try Task.checkCancellation()
                guard let url = request.url, let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                ) else { throw URLError(.badURL) }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch is CancellationError {
                // URLSession delivers cancellation to its awaiting caller.
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
    }
}
