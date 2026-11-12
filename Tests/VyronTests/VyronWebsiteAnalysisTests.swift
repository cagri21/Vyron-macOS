import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronWebsiteAnalysisTests: XCTestCase {
    func testSiteAnalysisUsesSitemapLinksAndRenderedPagesInTheSameReply() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        await test.model.loadWorkspace(test.base.project)
        test.model.composer.mode = .agent

        let root = try url("https://example.com/")
        let about = try url("https://example.com/about")
        let aboutFragment = try url("https://example.com/about#team")
        let rendered = try url("https://example.com/rendered")
        let renderedChild = try url("https://example.com/rendered-child")
        let sitemapOnly = try url("https://example.com/sitemap-only")
        let unavailable = try url("https://example.com/unavailable")
        let external = try url("https://example.org/another-website")
        let insecure = try url("http://example.com/insecure")
        let fixture = VyronWebsiteConversationAccess(
            pages: [
                root: page(
                    root, text: "ROOT_MARKER", links: [about, aboutFragment, rendered, unavailable, external, insecure]
                ),
                about: page(about, text: "ABOUT_MARKER", links: [root]),
                renderedChild: page(renderedChild, text: "RENDERED_CHILD_MARKER"),
                sitemapOnly: page(sitemapOnly, text: "SITEMAP_ONLY_MARKER")
            ],
            failures: [rendered: .unsupportedContent, unavailable: .unavailable],
            sitemap: [sitemapOnly, aboutFragment, external]
        )
        test.model.webAccess = fixture
        var renderedURLs: [URL] = []
        var renderedResponses: [VyronResponseIdentity] = []
        test.model.readRenderedWebPage = { url, response, scope in
            renderedURLs.append(url)
            renderedResponses.append(response)
            XCTAssertEqual(scope?.rootURL, root)
            guard url == rendered else {
                XCTFail("Unexpected browser fallback for \(url)")
                throw VyronWebError.unavailable
            }
            return self.page(url, text: "RENDERED_MARKER", links: [renderedChild, external])
        }
        test.model.composer.draft = "Analyze all subpages of \(root.absoluteString)"

        test.model.send()
        let response = try XCTUnwrap(test.model.foregroundRun.activeResponse)
        try await test.finishReply()

        let reads = await fixture.readURLs
        let sitemapRequests = await fixture.sitemapRequests
        let searches = await fixture.searchQueries
        let modelRequests = await test.provider.receivedMessages
        let developmentRequests = await test.provider.developmentRequests
        XCTAssertEqual(sitemapRequests, 1)
        XCTAssertTrue(searches.isEmpty)
        XCTAssertEqual(developmentRequests, 0)
        XCTAssertEqual(Set(reads), Set([root, about, rendered, renderedChild, sitemapOnly, unavailable]))
        XCTAssertEqual(reads.count, 6, "Fragments and repeated links must resolve to one page read.")
        XCTAssertEqual(renderedURLs, [rendered])
        XCTAssertEqual(renderedResponses, [response])
        XCTAssertEqual(modelRequests.count, 1)
        let request = try XCTUnwrap(modelRequests.first)
        let evidence = request.map(\.content).joined(separator: "\n")
        let markers = ["ROOT_MARKER", "ABOUT_MARKER", "RENDERED_MARKER", "RENDERED_CHILD_MARKER", "SITEMAP_ONLY_MARKER"]
        for marker in markers {
            XCTAssertTrue(evidence.contains(marker), marker)
        }
        XCTAssertFalse(evidence.contains(external.absoluteString))
        XCTAssertFalse(evidence.contains(insecure.absoluteString))

        let reply = try XCTUnwrap(test.model.messages.last)
        XCTAssertEqual(reply.id, response.messageID)
        XCTAssertEqual(reply.activity?.state, .completed)
        XCTAssertTrue(reply.content.contains("Web answer 1 grounded in supplied evidence."))
        let coverage = reply.content.components(separatedBy: "Pages that could not be read")
        let analyzed = try XCTUnwrap(coverage.first)
        let unreadable = try XCTUnwrap(coverage.dropFirst().first)
        XCTAssertTrue(analyzed.contains("Pages analyzed"))
        for url in [root, about, rendered, renderedChild, sitemapOnly] {
            XCTAssertTrue(analyzed.contains(url.absoluteString), "Analyzed pages should include \(url).")
        }
        XCTAssertFalse(analyzed.contains(unavailable.absoluteString))
        XCTAssertTrue(unreadable.contains(unavailable.absoluteString))
        XCTAssertFalse(reply.content.contains(external.absoluteString))
        XCTAssertFalse(reply.content.contains(insecure.absoluteString))
    }

    func testSiteAnalysisSkipsRenderedRedirectOutsideTheRequestedSite() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        let root = try url("https://example.com/")
        let redirect = try url("https://example.com/redirect")
        let external = try url("https://example.org/another-website")
        let fixture = VyronWebsiteConversationAccess(
            pages: [root: page(root, text: "ROOT_MARKER", links: [redirect])],
            failures: [redirect: .unsupportedContent],
            sitemap: []
        )
        test.model.webAccess = fixture
        test.model.readRenderedWebPage = { _, _, _ in
            self.page(external, text: "EXTERNAL_PAGE_MARKER", links: [external])
        }
        test.model.composer.draft = "Analyze the entire website \(root.absoluteString)"

        test.model.send()
        try await test.finishReply()

        let reads = await fixture.readURLs
        let requests = await test.provider.receivedMessages
        XCTAssertEqual(reads, [root, redirect])
        XCTAssertEqual(requests.count, 1)
        let evidence = try XCTUnwrap(requests.first).map(\.content).joined(separator: "\n")
        XCTAssertTrue(evidence.contains("ROOT_MARKER"))
        XCTAssertFalse(evidence.contains("EXTERNAL_PAGE_MARKER"))
        let reply = try XCTUnwrap(test.model.messages.last)
        XCTAssertEqual(reply.activity?.state, .completed)
        XCTAssertTrue(reply.content.contains(root.absoluteString))
        XCTAssertTrue(reply.content.contains(redirect.absoluteString))
        XCTAssertFalse(reply.content.contains(external.absoluteString))
    }

    func testSinglePageAnalysisDoesNotFollowLinksOrReadTheSitemap() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        let requested = try url("https://example.com/requested")
        let child = try url("https://example.com/linked")
        let fixture = VyronWebsiteConversationAccess(
            pages: [requested: page(requested, text: "REQUESTED_MARKER", links: [child])],
            failures: [:],
            sitemap: [child]
        )
        test.model.webAccess = fixture
        test.model.composer.draft = "Analyze \(requested.absoluteString)"

        test.model.send()
        try await test.finishReply()

        let reads = await fixture.readURLs
        let sitemaps = await fixture.sitemapRequests
        let requests = await test.provider.receivedMessages
        XCTAssertEqual(reads, [requested])
        XCTAssertEqual(sitemaps, 0)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests.first?.contains { $0.content.contains("REQUESTED_MARKER") } == true)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    func testSiteAnalysisBoundsDistinctPageAttemptsAndReportsAnalyzedPages() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        let root = try url("https://example.com/")
        let subpages = try (1...30).map { number in
            try url("https://example.com/article-\(String(format: "%02d", number))")
        }
        var pages = Dictionary(uniqueKeysWithValues: subpages.map { ($0, page($0, text: "ARTICLE_MARKER")) })
        pages[root] = page(root, text: "ROOT_MARKER", links: subpages)
        let fixture = VyronWebsiteConversationAccess(pages: pages, sitemap: subpages)
        test.model.webAccess = fixture
        test.model.composer.draft = "Analyze the entire website \(root.absoluteString)"

        test.model.send()
        try await test.finishReply()

        let reads = await fixture.readURLs
        XCTAssertEqual(reads.first, root)
        XCTAssertEqual(reads.count, 20)
        XCTAssertEqual(Set(reads).count, reads.count)
        let reply = try XCTUnwrap(test.model.messages.last)
        XCTAssertEqual(reply.activity?.state, .completed)
        XCTAssertTrue(reply.content.contains("Pages analyzed"))
        for url in reads {
            XCTAssertTrue(reply.content.contains(url.absoluteString))
        }
        for url in Set(subpages).subtracting(reads) {
            XCTAssertFalse(reply.content.contains(url.absoluteString))
        }
    }

    func testSiteAnalysisWithoutReadableEvidenceDoesNotAskTheModelToAnalyze() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        let root = try url("https://example.com/")
        let unavailable = try url("https://example.com/unavailable")
        let fixture = VyronWebsiteConversationAccess(
            pages: [:], failures: [root: .unavailable, unavailable: .unavailable], sitemap: [unavailable]
        )
        test.model.webAccess = fixture
        test.model.composer.draft = "Analyze the entire website \(root.absoluteString)"

        test.model.send()
        let response = try XCTUnwrap(test.model.foregroundRun.activeResponse)
        try await test.finishReply()

        let reads = await fixture.readURLs
        let requests = await test.provider.receivedMessages
        XCTAssertEqual(reads, [root, unavailable])
        XCTAssertTrue(requests.isEmpty)
        let reply = try XCTUnwrap(test.model.messages.last)
        XCTAssertEqual(reply.id, response.messageID)
        XCTAssertEqual(reply.activity?.state, .failed)
    }

    func testStoppedSiteAnalysisCannotFollowLinksFromALateRenderedPage() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        let root = try url("https://example.com/")
        let staleChild = try url("https://example.com/stale-child")
        let replacementPage = try url("https://example.com/replacement")
        let fixture = VyronWebsiteConversationAccess(
            pages: [replacementPage: page(replacementPage, text: "REPLACEMENT_MARKER")],
            failures: [root: .unsupportedContent]
        )
        test.model.webAccess = fixture
        var pendingRender: CheckedContinuation<VyronWebPage, Error>?
        var renderReturned = false
        test.model.readRenderedWebPage = { _, _, _ in
            let page = try await withCheckedThrowingContinuation { pendingRender = $0 }
            renderReturned = true
            return page
        }
        defer { pendingRender?.resume(throwing: CancellationError()) }
        test.model.composer.draft = "Analyze the entire website \(root.absoluteString)"
        test.model.send()
        try await test.base.waitUntil { pendingRender != nil }
        let stoppedID = try XCTUnwrap(test.model.messages.last?.id)

        test.model.stopGeneration()
        test.model.composer.draft = "Analyze \(replacementPage.absoluteString)"
        test.model.send()
        try await test.finishReply()
        let replacement = try XCTUnwrap(test.model.messages.last)

        let render = try XCTUnwrap(pendingRender)
        pendingRender = nil
        render.resume(returning: page(root, text: "STALE_MARKER", links: [staleChild]))
        try await test.base.waitUntil { renderReturned }
        for _ in 0..<20 { await Task.yield() }

        let reads = await fixture.readURLs
        let requests = await test.provider.receivedMessages
        XCTAssertEqual(reads, [root, replacementPage])
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests.first?.contains { $0.content.contains("REPLACEMENT_MARKER") } == true)
        XCTAssertEqual(test.model.messages.first { $0.id == stoppedID }?.activity?.state, .stopped)
        XCTAssertEqual(test.model.messages.last, replacement)
    }

    private func url(_ address: String) throws -> URL {
        try XCTUnwrap(URL(string: address))
    }

    private func page(_ url: URL, text: String, links: [URL] = []) -> VyronWebPage {
        VyronWebPage(
            source: VyronWebSource(title: url.lastPathComponent, url: url, excerpt: ""), text: text, links: links
        )
    }
}
