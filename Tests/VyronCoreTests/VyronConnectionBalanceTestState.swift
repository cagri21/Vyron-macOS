import Foundation

actor VyronConnectionBalanceTestState {
    typealias Handler = @Sendable (URLRequest) throws -> VyronConnectionBalanceTestReply

    private var handler: Handler?
    private(set) var requests: [URLRequest] = []
    private(set) var stopCount = 0

    func configure(_ handler: Handler? = nil) {
        self.handler = handler
        requests = []
        stopCount = 0
    }

    func response(for request: URLRequest) throws -> VyronConnectionBalanceTestReply {
        requests.append(request)
        guard let handler else { throw URLError(.unsupportedURL) }
        return try handler(request)
    }

    func stopped() { stopCount += 1 }
}
