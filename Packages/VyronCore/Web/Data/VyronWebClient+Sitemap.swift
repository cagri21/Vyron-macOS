import Foundation

extension VyronWebClient {
    public func sitemapPages(in scope: VyronWebsiteScope) async throws -> [URL] {
        try await VyronWebsiteSitemapDiscovery().pageURLs(in: scope)
    }
}
