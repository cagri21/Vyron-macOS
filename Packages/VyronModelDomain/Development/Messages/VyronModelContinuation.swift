import Foundation

/// Opaque continuation state travels with its assistant exchange, including encoded copies of that exchange.
/// Only the originating model adapter interprets the state; it is never displayed or added to prompt text.
public struct VyronModelContinuation: Codable, Sendable, Equatable {
    public let source: String
    public let model: String
    public let state: Data

    public init(source: String, model: String, state: Data) {
        self.source = source
        self.model = model
        self.state = state
    }
}
