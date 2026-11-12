import Foundation

/// A genuine JSON transport DTO shared with the extension; optional keys retain the wire contract.
public struct VyronChromeBridgeArguments: Codable, Sendable, Equatable {
    public var tabID: Int?
    public var snapshotID: String?
    public var elementID: Int?
    public var text: String?
    public var url: String?

    public init() {}
}
