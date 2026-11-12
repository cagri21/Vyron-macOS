import Foundation

protocol VyronWebTransport: Sendable {
    func fetch(_ url: URL) async throws -> VyronWebResponse
}
