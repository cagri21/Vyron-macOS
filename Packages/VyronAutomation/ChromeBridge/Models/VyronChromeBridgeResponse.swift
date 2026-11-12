import Foundation

/// External JSON response; result is deliberately a JSON value rather than an untyped dictionary.
public struct VyronChromeBridgeResponse: Codable, Sendable, Equatable {
    public let version: Int
    public let id: UUID
    public let ok: Bool
    public let result: VyronChromeJSONValue?
    public let error: String?

    public func encodedJSON() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }

    func validate() throws {
        guard version == 1, (error?.utf8.count ?? 0) <= 8_192,
            ok ? error == nil : (error?.isEmpty == false)
        else { throw VyronChromeBridgeError.invalidMessage }
    }
}
