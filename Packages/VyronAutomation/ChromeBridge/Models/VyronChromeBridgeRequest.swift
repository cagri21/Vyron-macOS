import Foundation

/// Native messaging transport, with an immutable identity and an absolute expiry to prevent replay.
public struct VyronChromeBridgeRequest: Codable, Sendable, Equatable {
    public let version: Int
    public let id: UUID
    public let method: String
    public let arguments: VyronChromeBridgeArguments
    public let expiresAt: Double

    public init(method: String, arguments: VyronChromeBridgeArguments = .init()) {
        version = 1
        id = UUID()
        self.method = method
        self.arguments = arguments
        expiresAt = Date().addingTimeInterval(30).timeIntervalSince1970 * 1_000
    }

    func validate(now: Date = Date()) throws {
        let remaining = expiresAt / 1_000 - now.timeIntervalSince1970
        guard version == 1, VyronChromeBridgePolicy.methods.contains(method),
            expiresAt.isFinite, remaining > 0, remaining <= 35,
            arguments.tabID.map({ $0 >= 0 }) ?? true,
            arguments.elementID.map({ $0 >= 0 }) ?? true,
            arguments.snapshotID.map({ UUID(uuidString: $0) != nil }) ?? true,
            (arguments.text?.utf8.count ?? 0) <= 12_000,
            (arguments.url?.utf8.count ?? 0) <= 8_192
        else { throw VyronChromeBridgeError.invalidMessage }
        if method != "tabs", arguments.tabID == nil { throw VyronChromeBridgeError.invalidMessage }
        if ["click", "fill"].contains(method),
            arguments.snapshotID == nil || arguments.elementID == nil {
            throw VyronChromeBridgeError.invalidMessage
        }
        if method == "fill", arguments.text == nil { throw VyronChromeBridgeError.invalidMessage }
        if method == "navigate" {
            guard let value = arguments.url, let parts = URLComponents(string: value),
                ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
                parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
                !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw VyronChromeBridgeError.invalidMessage }
        }
    }
}
