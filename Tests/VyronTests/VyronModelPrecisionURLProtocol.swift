import Foundation
import os

/// Each fixture has its own endpoint. All requests terminate here without reaching the network.
final class VyronModelPrecisionURLProtocol: URLProtocol, @unchecked Sendable {
    private static let transports = OSAllocatedUnfairLock(initialState: [Int: VyronModelPrecisionTransport]())

    static func register(_ transport: VyronModelPrecisionTransport, port: Int) {
        transports.withLock { $0[port] = transport }
    }

    static func unregister(port: Int) {
        _ = transports.withLock { $0.removeValue(forKey: port) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let port = url.port,
              let transport = Self.transports.withLock({ $0[port] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        transport.handle(request) { status, body in
            guard let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/x-ndjson"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !body.isEmpty { client?.urlProtocol(self, didLoad: Data(body.utf8)) }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        // Held requests have no pending callback. URLSession delivers cancellation to the caller.
    }
}
