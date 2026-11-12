import Foundation

/// Sensitive restoration candidate. The presentation owner must recheck current profile ownership before applying it.
public struct VyronLocalCredentialRestoration: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let connectionID: UUID
    public let key: String

    public init(connectionID: UUID, key: String) {
        self.connectionID = connectionID
        self.key = key
    }

    public var description: String { "VyronLocalCredentialRestoration(connectionID: \(connectionID), key: <redacted>)" }
    public var debugDescription: String { description }
}
