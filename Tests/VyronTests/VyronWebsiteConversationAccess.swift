import Foundation
import XCTest
import VyronCore

actor VyronWebsiteConversationAccess: VyronWebAccessing {
    private let pages: [URL: VyronWebPage]
    private let failures: [URL: VyronWebError]
    private let sitemap: [URL]
    private(set) var searchQueries: [String] = []
    private(set) var readURLs: [URL] = []
    private(set) var sitemapRequests = 0

    init(pages: [URL: VyronWebPage], failures: [URL: VyronWebError] = [:], sitemap: [URL] = []) {
        self.pages = pages
        self.failures = failures
        self.sitemap = sitemap
    }

    func search(query: String) async throws -> [VyronWebSource] {
        searchQueries.append(query)
        throw VyronWebError.noResults
    }

    func read(url: URL) async throws -> VyronWebPage {
        readURLs.append(url)
        if let failure = failures[url] { throw failure }
        guard let page = pages[url] else {
            XCTFail("Unexpected page read for \(url)")
            throw VyronWebError.unavailable
        }
        return page
    }

    func sitemapPages(in scope: VyronWebsiteScope) async throws -> [URL] {
        sitemapRequests += 1
        return sitemap
    }
}
