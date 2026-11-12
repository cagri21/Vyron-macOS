import Foundation

enum VyronWorkspaceAddress {
    static func resolve(_ rawValue: String) -> VyronWorkspaceAddressResolution {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .controlCharacters) == nil else { return .invalid }
        if value.contains("://") {
            guard let url = URL(string: value), isAllowedWebsite(url) else { return .invalid }
            return .website(VyronWorkspaceWebsiteLocation(url: url))
        }
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            let components = URLComponents(string: "https://\(value)"),
            let host = components.host, isAddressHost(host) {
            guard components.user == nil, components.password == nil else { return .invalid }
            var website = components
            website.scheme = isLoopbackHost(host) ? "http" : "https"
            guard let url = website.url, isAllowedWebsite(url) else { return .invalid }
            return .website(VyronWorkspaceWebsiteLocation(url: url))
        }
        // A scheme-like prefix is an address attempt. Never turn an unsupported scheme into a web visit.
        if value.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil {
            return .invalid
        }
        var search = URLComponents()
        search.scheme = "https"
        search.host = "duckduckgo.com"
        search.path = "/"
        search.queryItems = [URLQueryItem(name: "q", value: value)]
        guard let url = search.url else { return .invalid }
        return .website(VyronWorkspaceWebsiteLocation(url: url))
    }

    static func isAllowedWebsite(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.port.map({ (1...65_535).contains($0) }) != false,
            host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            host.rangeOfCharacter(from: .controlCharacters) == nil,
            url.absoluteString.rangeOfCharacter(from: .controlCharacters) == nil
        else { return false }
        return true
    }

    private static func isAddressHost(_ host: String) -> Bool {
        if isLoopbackHost(host) { return true }
        if isIPv4Host(host) { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1, labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 }) else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return labels.allSatisfy {
            !$0.hasPrefix("-") && !$0.hasSuffix("-")
                && $0.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    private static func isIPv4Host(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count == 4 && labels.allSatisfy {
            !$0.isEmpty && $0.allSatisfy(\.isNumber) && UInt8($0) != nil
        }
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return normalized == "localhost" || normalized.hasSuffix(".localhost") || normalized == "::1"
            || (normalized.hasPrefix("127.") && isIPv4Host(normalized))
    }
}
