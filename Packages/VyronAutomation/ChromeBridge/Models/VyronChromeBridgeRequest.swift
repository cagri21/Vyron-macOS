import Foundation

/// Native messaging transport, with an immutable identity and an absolute expiry to prevent replay.
public struct VyronChromeBridgeRequest: Codable, Sendable, Equatable {
    public static let maximumOpenTabCount = 8
    public static let maximumGroupTitleBytes = 80
    public static let maximumOpenTabURLBytes = 8_192

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

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        id = try values.decode(UUID.self, forKey: .id)
        method = try values.decode(String.self, forKey: .method)
        expiresAt = try values.decode(Double.self, forKey: .expiresAt)
        if method == VyronChromeBridgePolicy.openTabsMethod {
            let fields = try values.decode([String: VyronChromeJSONValue].self, forKey: .arguments)
            guard Set(fields.keys) == ["urls", "groupTitle"] else { throw VyronChromeBridgeError.invalidMessage }
        }
        arguments = try values.decode(VyronChromeBridgeArguments.self, forKey: .arguments)
    }

    public static func openTabs(urls: [String], groupTitle: String) throws -> Self {
        var arguments = VyronChromeBridgeArguments()
        arguments.urls = urls
        arguments.groupTitle = groupTitle
        let request = Self(method: VyronChromeBridgePolicy.openTabsMethod, arguments: arguments)
        try request.validate()
        return request
    }

    func validate(now: Date = Date()) throws {
        let remaining = expiresAt / 1_000 - now.timeIntervalSince1970
        guard version == 1, VyronChromeBridgePolicy.methods.contains(method),
            expiresAt.isFinite, remaining > 0, remaining <= 35
        else { throw VyronChromeBridgeError.invalidMessage }
        if method == VyronChromeBridgePolicy.openTabsMethod {
            try validateOpenTabsArguments()
            return
        }
        guard arguments.urls == nil, arguments.groupTitle == nil,
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

    private func validateOpenTabsArguments() throws {
        guard arguments.tabID == nil, arguments.snapshotID == nil, arguments.elementID == nil,
            arguments.text == nil, arguments.url == nil,
            let urls = arguments.urls, (1...Self.maximumOpenTabCount).contains(urls.count),
            urls.allSatisfy(Self.isOpenTabURL),
            let title = arguments.groupTitle, !title.isEmpty, title.utf8.count <= Self.maximumGroupTitleBytes,
            title == title.trimmingCharacters(in: .whitespacesAndNewlines),
            title.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw VyronChromeBridgeError.invalidMessage }
    }

    private static func isOpenTabURL(_ value: String) -> Bool {
        guard value.utf8.count <= maximumOpenTabURLBytes,
            value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
            !value.contains("\\"), let parts = URLComponents(string: value),
            let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
            value.prefix(scheme.count + 3).lowercased() == scheme + "://",
            let host = parts.host, !host.isEmpty, parts.url != nil,
            parts.user == nil, parts.password == nil
        else { return false }
        return parts.port.map { (0...65_535).contains($0) } ?? true
    }
}
