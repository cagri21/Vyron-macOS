import Foundation
@testable import VyronCore

struct VyronWebTestTransport: VyronWebTransport {
    let handler: @Sendable (URL) async throws -> VyronWebResponse

    func fetch(_ url: URL) async throws -> VyronWebResponse {
        try await handler(url)
    }
}
