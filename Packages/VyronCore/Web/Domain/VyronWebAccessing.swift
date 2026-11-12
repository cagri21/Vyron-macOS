import Foundation

public protocol VyronWebAccessing: Sendable {
    func search(query: String) async throws -> [VyronWebSource]
    func read(url: URL) async throws -> VyronWebPage
    func sitemapPages(in scope: VyronWebsiteScope) async throws -> [URL]
}

public extension VyronWebAccessing {
    func sitemapPages(in scope: VyronWebsiteScope) async throws -> [URL] {
        try Task.checkCancellation()
        return []
    }
}
