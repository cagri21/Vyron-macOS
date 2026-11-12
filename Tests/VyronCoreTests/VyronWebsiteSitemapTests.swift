import Foundation
import XCTest
@testable import VyronCore

final class VyronWebsiteSitemapTests: XCTestCase, @unchecked Sendable {
    func testScopeCanonicalizesSameOriginWithoutDiscardingQueryParameters() throws {
        let scope = try makeScope("https://EXAMPLE.com:443/docs/index?view=full#summary")
        XCTAssertEqual(scope.rootURL.absoluteString, "https://example.com/")
        XCTAssertEqual(scope.seedURL.absoluteString, "https://example.com/docs/index?view=full")
        let relative = try XCTUnwrap(URL(string: "../about?lang=tr#details", relativeTo: scope.seedURL))
        XCTAssertEqual(scope.canonicalPageURL(relative)?.absoluteString, "https://example.com/about?lang=tr")
        let root = try XCTUnwrap(URL(string: "https://example.com#top"))
        XCTAssertEqual(scope.canonicalPageURL(root), scope.rootURL)

        for value in [
            "http://example.com/about", "https://www.example.com/about", "https://example.com:8443/about",
            "https://example.com.other.org/about", "https://user@example.com/about", "https://127.0.0.1/about"
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(scope.canonicalPageURL(url), value)
        }
    }

    func testDiscoverDeclaredAndDefaultSitemapsAndFollowIndexOnce() async throws {
        let scope = try makeScope()
        let discovery = VyronWebsiteSitemapDiscovery(transport: VyronWebTestTransport { url in
            let document: String
            switch url.path {
            case "/robots.txt":
                document = """
                User-agent: *
                Sitemap: https://other.com/unrelated.xml
                sItEmAp : /catalog/maps.xml # this is the index
                Sitemap: https://example.com/catalog/maps.xml#duplicate
                """
            case "/catalog/maps.xml":
                document = """
                <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
                  <sitemap><loc>https://example.com/catalog/pages.xml</loc></sitemap>
                  <sitemap><loc>https://example.com/catalog/maps.xml</loc></sitemap>
                  <sitemap><loc>https://other.com/not-ours.xml</loc></sitemap>
                </sitemapindex>
                """
            case "/sitemap.xml":
                document = """
                <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
                        xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
                  <url><loc>https://example.com/docs?x=1&amp;y=2#intro</loc>
                    <image:image><image:loc>https://example.com/asset.jpg</image:loc></image:image>
                  </url>
                </urlset>
                """
            case "/catalog/pages.xml":
                document = """
                <urlset>
                  <url><loc>https://EXAMPLE.com:443/docs?x=1&amp;y=2</loc></url>
                  <url><loc><![CDATA[../about]]></loc></url>
                  <url><loc>https://external.com/products</loc></url>
                </urlset>
                """
            default:
                XCTFail("Unexpected sitemap fetch \(url)")
                throw VyronWebError.unavailable
            }
            XCTAssertEqual(url.host, "example.com")
            return VyronWebResponse(url: url, mediaType: "text/xml", body: Data(document.utf8))
        })

        let pages = try await discovery.pageURLs(in: scope)
        XCTAssertEqual(pages.map(\.absoluteString), ["https://example.com/docs?x=1&y=2", "https://example.com/about"])
    }

    func testUnavailableMetadataAndExternalEntityDeclarationsLeaveDiscoveryEmpty() async throws {
        let scope = try makeScope()
        let discovery = VyronWebsiteSitemapDiscovery(transport: VyronWebTestTransport { url in
            if url.path == "/robots.txt" { throw VyronWebError.unavailable }
            XCTAssertEqual(url.path, "/sitemap.xml")
            let document = """
            <!DOCTYPE urlset [<!ENTITY external SYSTEM "https://example.com/external.xml">]>
            <urlset><url><loc>https://example.com/public</loc></url><url><loc>&external;</loc></url></urlset>
            """
            return VyronWebResponse(url: url, mediaType: "text/xml", body: Data(document.utf8))
        })

        let pages = try await discovery.pageURLs(in: scope)
        XCTAssertTrue(pages.isEmpty)
    }

    func testDiscoveryCapsSitemapIndexRequestsAndUniquePageCandidates() async throws {
        let scope = try makeScope()
        let discovery = VyronWebsiteSitemapDiscovery(transport: VyronWebTestTransport { url in
            let document: String
            switch url.path {
            case "/robots.txt":
                throw VyronWebError.unavailable
            case "/sitemap.xml":
                let maps = (0..<10).map { "<sitemap><loc>/map-\($0).xml</loc></sitemap>" }.joined()
                document = "<sitemapindex>\(maps)</sitemapindex>"
            case "/map-0.xml", "/map-1.xml", "/map-2.xml":
                throw VyronWebError.unavailable
            case "/map-3.xml":
                let pages = (0..<240).map { "<url><loc>/page-\($0)</loc></url>" }.joined()
                document = "<urlset>\(pages)</urlset>"
            default:
                XCTFail("Discovery exceeded its sitemap request cap \(url)")
                throw VyronWebError.unavailable
            }
            return VyronWebResponse(url: url, mediaType: "text/xml", body: Data(document.utf8))
        })

        let pages = try await discovery.pageURLs(in: scope)
        XCTAssertEqual(pages.count, 200)
        XCTAssertEqual(pages.last?.path, "/page-199")
    }

    func testDiscoveryPropagatesCancellationBeforeTryingAnotherSitemap() async throws {
        let scope = try makeScope()
        let discovery = VyronWebsiteSitemapDiscovery(transport: VyronWebTestTransport { url in
            XCTAssertEqual(url.path, "/robots.txt")
            throw CancellationError()
        })

        do {
            _ = try await discovery.pageURLs(in: scope)
            XCTFail("Expected cancelled discovery")
        } catch is CancellationError {
            return
        }
    }

    func testDiscoveryReadsGzippedXMLWithinTheDecompressedByteLimit() async throws {
        let encoded = "H4sIAAAAAAAC/7MpLcopTi2xUxgFIxrYANOBnU1OfrJdRklJQbGVvn5qRWJuQU6qXnJ+rj4QFxSlFhenptjog9TY6IOV60MTDwAh5XVYRQIAAA=="
        let compressed = try XCTUnwrap(Data(base64Encoded: encoded))
        XCTAssertLessThan(compressed.count, 150)
        XCTAssertNil(VyronWebsiteSitemapCompression.decodeIfNeeded(compressed, maximumBytes: 150))
        XCTAssertNil(VyronWebsiteSitemapCompression.decodeIfNeeded(compressed.dropLast(), maximumBytes: 1_000))
        let scope = try makeScope()
        let discovery = VyronWebsiteSitemapDiscovery(transport: VyronWebTestTransport { url in
            if url.path == "/robots.txt" {
                let robots = "Sitemap: https://example.com/compressed.xml.gz"
                return VyronWebResponse(url: url, mediaType: "text/plain", body: Data(robots.utf8))
            }
            if url.path == "/sitemap.xml" { throw VyronWebError.unavailable }
            XCTAssertEqual(url.path, "/compressed.xml.gz")
            return VyronWebResponse(url: url, mediaType: "application/gzip", body: compressed)
        })

        let pages = try await discovery.pageURLs(in: scope)
        XCTAssertEqual(pages.map(\.absoluteString), ["https://example.com/compressed"])
    }

    private func makeScope(_ value: String = "https://example.com/docs") throws -> VyronWebsiteScope {
        try VyronWebsiteScope(seedURL: XCTUnwrap(URL(string: value)))
    }
}
