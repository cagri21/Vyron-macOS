import Foundation

/// Sanitized retry advice retains the existing status without exposing response headers or bodies.
public struct VyronConnectionBalanceRetryFailure: Error, LocalizedError, Equatable, Sendable {
    public let error: VyronConnectionBalanceError
    public let retryAfter: Date?

    public init(error: VyronConnectionBalanceError, retryAfter: Date?) {
        self.error = error
        self.retryAfter = retryAfter
    }

    public var errorDescription: String? { error.errorDescription }
}
