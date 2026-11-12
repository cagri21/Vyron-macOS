import Foundation

/// Same HTTPS origin as the requested website. Fetching adapters validate resolved addresses.
public struct VyronWebsiteScope: Sendable {
    static let maximumURLBytes = 2_048

    public let seedURL: URL
    public let rootURL: URL
    private let host: String

    public init(seedURL: URL) throws {
        let seedURL = try Self.canonicalURL(seedURL)
        guard let host = seedURL.host else { throw VyronWebError.unsafeURL }
        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = host
        origin.path = "/"
        guard let rootURL = origin.url else { throw VyronWebError.unsafeURL }
        self.seedURL = seedURL
        self.rootURL = rootURL
        self.host = host
    }

    public func canonicalPageURL(_ url: URL) -> URL? {
        do {
            let candidate = try Self.canonicalURL(url)
            return candidate.host == host ? candidate : nil
        } catch {
            return nil
        }
    }

    func canonicalPageURL(_ location: String, relativeTo baseURL: URL) -> URL? {
        let value = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let url = URL(string: value, relativeTo: baseURL) else { return nil }
        return canonicalPageURL(url)
    }

    private static func canonicalURL(_ url: URL) throws -> URL {
        guard url.absoluteString.utf8.count <= maximumURLBytes else {
            throw VyronWebError.unsafeURL
        }
        let validated = try VyronWebURLPolicy.validated(url.absoluteURL)
        guard var components = URLComponents(url: validated.standardized, resolvingAgainstBaseURL: false) else {
            throw VyronWebError.unsafeURL
        }
        components.scheme = "https"
        components.host = components.host?.lowercased()
        components.port = nil
        if components.percentEncodedPath.isEmpty { components.percentEncodedPath = "/" }
        guard let canonical = components.url else { throw VyronWebError.unsafeURL }
        return canonical
    }
}
