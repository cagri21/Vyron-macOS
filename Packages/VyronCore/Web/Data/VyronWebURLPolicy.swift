import Foundation

public enum VyronWebURLPolicy {
    /// Checks the URL and its resolved addresses, returning the fragment-free URL used for HTTP requests.
    @discardableResult
    public static func validatePublicHTTPS(_ url: URL) async throws -> URL {
        let target = try validated(url)
        guard let host = target.host else { throw VyronWebError.unsafeURL }
        try await VyronWebHostValidator.validate(host)
        return target
    }

    static func validated(_ url: URL) throws -> URL {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
            parts.port == nil || parts.port == 443, let host = parts.host?.lowercased(),
            host.utf8.count <= 253, !host.hasSuffix("."), host.contains("."),
            !host.contains(":"), !host.allSatisfy({ $0.isNumber || $0 == "." }),
            !host.hasPrefix("0x"), !host.hasPrefix("0X")
        else { throw VyronWebError.unsafeURL }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 45 }
        }), labels.last?.allSatisfy(\.isNumber) == false,
            !["localhost", "local", "internal", "lan", "home", "onion", "invalid"]
                .contains(String(labels.last ?? ""))
        else { throw VyronWebError.unsafeURL }
        var normalized = parts
        normalized.fragment = nil
        guard let result = normalized.url else { throw VyronWebError.unsafeURL }
        return result
    }
}
