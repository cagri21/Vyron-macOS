import Foundation

public protocol VyronLocalAuthTransport: Sendable {
    func data(for request: URLRequest) async throws -> VyronLocalAuthHTTPResponse
}
