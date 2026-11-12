import Foundation

public enum VyronWebsiteCrawler {
    public static let maximumPages = 20

    public static func crawl(
        in scope: VyronWebsiteScope,
        sitemap: [URL],
        readPage: @Sendable (URL) async throws -> VyronWebPage
    ) async throws -> VyronWebsiteCrawl {
        var linked = [scope.seedURL, scope.rootURL][...]
        var mapped = sitemap.compactMap(scope.canonicalPageURL)[...]
        var visited = Set<URL>()
        var readable = Set<URL>()
        var pages: [VyronWebPage] = []
        var unreadableURLs: [URL] = []
        var attempts = 0

        while attempts < maximumPages {
            try Task.checkCancellation()
            // Alternate sources so large sitemaps leave room for pages only found through links.
            let candidate = attempts.isMultiple(of: 2)
                ? linked.popFirst() ?? mapped.popFirst()
                : mapped.popFirst() ?? linked.popFirst()
            guard let url = candidate else { break }
            guard visited.insert(url).inserted else { continue }
            attempts += 1
            do {
                let page = try await readPage(url)
                try Task.checkCancellation()
                guard let canonical = scope.canonicalPageURL(page.source.url),
                    !page.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    unreadableURLs.append(url)
                    continue
                }
                visited.insert(canonical)
                guard readable.insert(canonical).inserted else { continue }
                pages.append(page)
                linked.append(contentsOf: page.links.compactMap(scope.canonicalPageURL))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                unreadableURLs.append(url)
            }
        }

        let hasRemainingPages = linked.contains { !visited.contains($0) }
            || mapped.contains { !visited.contains($0) }
        return VyronWebsiteCrawl(
            pages: pages,
            unreadableURLs: unreadableURLs.filter { !readable.contains($0) },
            reachedPageLimit: hasRemainingPages
        )
    }
}
