import Foundation

public enum VyronWebPageLinks {
    public static let maximumCount = 128
    public static let maximumURLBytes = VyronWebsiteScope.maximumURLBytes

    public static func sameSite(_ candidates: some Sequence<URL>, from url: URL) throws -> [URL] {
        try Task.checkCancellation()
        guard url.absoluteString.utf8.count <= maximumURLBytes else { return [] }
        let scope = try VyronWebsiteScope(seedURL: url)
        var seen: Set<URL> = [scope.seedURL]
        var links: [URL] = []
        for candidate in candidates {
            try Task.checkCancellation()
            guard candidate.absoluteString.utf8.count <= maximumURLBytes,
                let link = scope.canonicalPageURL(candidate), seen.insert(link).inserted
            else { continue }
            links.append(link)
            if links.count == maximumCount { break }
        }
        return links
    }
}
