import Foundation

struct VyronWebsiteSitemapDiscovery: Sendable {
    private let transport: any VyronWebTransport

    init(transport: any VyronWebTransport = VyronWebURLSessionTransport(
        acceptedMediaTypes: VyronWebsiteSitemapLimits.metadataMediaTypes,
        requestTimeout: VyronWebsiteSitemapLimits.requestTimeout,
        resourceTimeout: VyronWebsiteSitemapLimits.resourceTimeout
    )) {
        self.transport = transport
    }

    func pageURLs(in scope: VyronWebsiteScope) async throws -> [URL] {
        var sitemapURLs = try await declaredSitemapURLs(in: scope)
        let defaultSitemapURL = scope.rootURL.appendingPathComponent("sitemap.xml")
        var seenSitemaps = Set(sitemapURLs)
        if seenSitemaps.insert(defaultSitemapURL).inserted { sitemapURLs.append(defaultSitemapURL) }
        var seenPages: Set<URL> = []
        var pageURLs: [URL] = []
        var index = 0
        while index < min(sitemapURLs.count, VyronWebsiteSitemapLimits.sitemapDocuments) {
            let sitemapURL = sitemapURLs[index]
            index += 1
            guard let bytes = try await fetchMetadata(at: sitemapURL),
                let data = VyronWebsiteSitemapCompression.decodeIfNeeded(
                    bytes, maximumBytes: VyronWebLimits.responseBytes
                ),
                let document = VyronWebsiteSitemapParser.parse(data, scope: scope, baseURL: sitemapURL)
            else { continue }
            try Task.checkCancellation()
            if document.isIndex {
                for url in document.locations where sitemapURLs.count < VyronWebsiteSitemapLimits.sitemapDocuments {
                    if seenSitemaps.insert(url).inserted { sitemapURLs.append(url) }
                }
            } else {
                for url in document.locations where seenPages.insert(url).inserted {
                    pageURLs.append(url)
                    if pageURLs.count == VyronWebsiteSitemapLimits.pageCandidates { return pageURLs }
                }
            }
        }
        try Task.checkCancellation()
        return pageURLs
    }

    private func declaredSitemapURLs(in scope: VyronWebsiteScope) async throws -> [URL] {
        let robotsURL = scope.rootURL.appendingPathComponent("robots.txt")
        guard let data = try await fetchMetadata(at: robotsURL), let robots = String(data: data, encoding: .utf8) else {
            return []
        }
        var seen: Set<URL> = []
        var urls: [URL] = []
        for line in robots.split(whereSeparator: \.isNewline) {
            let entry = line.prefix(while: { $0 != "#" }).split(separator: ":", maxSplits: 1)
            guard entry.count == 2, entry[0].trimmingCharacters(in: .whitespaces).lowercased() == "sitemap",
                let url = scope.canonicalPageURL(String(entry[1]), relativeTo: robotsURL), seen.insert(url).inserted
            else { continue }
            urls.append(url)
            if urls.count == VyronWebsiteSitemapLimits.sitemapDocuments - 1 { break }
        }
        return urls
    }

    private func fetchMetadata(at url: URL) async throws -> Data? {
        do {
            try Task.checkCancellation()
            let response = try await transport.fetch(url)
            try Task.checkCancellation()
            guard response.url == url, response.body.count <= VyronWebLimits.responseBytes else { return nil }
            return response.body
        } catch is VyronWebError {
            try Task.checkCancellation()
            return nil
        }
    }
}
