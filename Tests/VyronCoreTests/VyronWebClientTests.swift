import Foundation
import XCTest
@testable import VyronCore

final class VyronWebClientTests: XCTestCase, @unchecked Sendable {
    func testSearchSendsOnlyEncodedQueryAndPreservesSourceURLs() async throws {
        let client = VyronWebClient(transport: VyronWebTestTransport { url in
            XCTAssertEqual(url.host, "html.duckduckgo.com")
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "q", value: "İstanbul pharmacies & hours")])
            return VyronWebResponse(url: url, mediaType: "text/html", body: Data("""
            <html><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fpharmacy%3Fcity%3Distanbul&amp;rut=x">Pharmacy &amp; hours</a>
            <a class="result__snippet">Verified &#304;stanbul addresses <b>and</b> opening times.</a>
            <a href="https://example.org/list" class="result__a">Another source</a>
            <div class="result__snippet">A separate list.</div></html>
            """.utf8))
        })
        let results = try await client.search(query: " İstanbul\npharmacies & hours ")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].url.absoluteString, "https://example.com/pharmacy?city=istanbul")
        XCTAssertEqual(results[0].title, "Pharmacy & hours")
        XCTAssertEqual(results[0].excerpt, "Verified İstanbul addresses and opening times.")
        XCTAssertEqual(results[1].excerpt, "A separate list.")
    }

    func testSearchDeduplicatesFiltersUnsafeLinksAndBoundsResults() async throws {
        let client = VyronWebClient(transport: VyronWebTestTransport { url in
            let anchors = (0..<30).map { index in
                "<a class='result__a' href='https://example.com/\(index)'>Result \(index)</a>"
            }.joined()
            let html = """
            <a class='result__a' href='https://127.0.0.1/'>Private</a>
            <a class='result__a' href='file:///tmp/private'>File</a>
            <a class='result__a' href='https://example.com/0'>Duplicate</a>
            \(anchors)
            """
            return VyronWebResponse(url: url, mediaType: "text/html", body: Data(html.utf8))
        })
        let result = try await client.search(query: "public list")
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(Set(result.map(\.url)).count, 10)
        XCTAssertTrue(result.allSatisfy { $0.url.host == "example.com" })
    }

    func testInvalidQueriesAreRejectedBeforeTransport() async throws {
        let client = VyronWebClient(transport: VyronWebTestTransport { _ in
            XCTFail("An invalid query must not leave the app")
            throw VyronWebError.unavailable
        })
        for query in ["   ", "hello\u{0000}world", String(repeating: "a", count: 2_001)] {
            do {
                _ = try await client.search(query: query)
                XCTFail("Expected invalid query")
            } catch { XCTAssertEqual(error as? VyronWebError, .invalidQuery) }
        }
    }

    func testNoResultsAndServiceFailureAreSurfacedWithoutFabricatedSources() async throws {
        let emptyClient = VyronWebClient(transport: VyronWebTestTransport { url in
            VyronWebResponse(url: url, mediaType: "text/html", body: Data("<html>Challenge or no results</html>".utf8))
        })
        do {
            _ = try await emptyClient.search(query: "pharmacies")
            XCTFail("Expected no readable results")
        } catch { XCTAssertEqual(error as? VyronWebError, .noResults) }
        let failingClient = VyronWebClient(transport: VyronWebTestTransport { _ in
            throw VyronWebError.unavailable
        })
        do {
            _ = try await failingClient.search(query: "pharmacies")
            XCTFail("Expected service failure")
        } catch { XCTAssertEqual(error as? VyronWebError, .unavailable) }
    }

    func testReadRemovesExecutableMarkupAndKeepsRetrievalAndSource() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/pharmacy#section"))
        let client = VyronWebClient(transport: VyronWebTestTransport { target in
            XCTAssertNil(target.fragment)
            return VyronWebResponse(url: target, mediaType: "text/html", body: Data("""
            <html><head><title>İstanbul &amp; hours</title><style>.secret {}</style></head>
            <body><script>DO_NOT_USE_THIS</script><h1>Pharmacy</h1><p>Open until 20:00.</p>
            <!-- hidden --><noscript>hidden fallback</noscript></body></html>
            """.utf8))
        })
        let started = Date()
        let page = try await client.read(url: url)
        XCTAssertEqual(page.source.url.absoluteString, "https://example.com/pharmacy")
        XCTAssertEqual(page.source.title, "İstanbul & hours")
        XCTAssertEqual(page.text, "Pharmacy Open until 20:00.")
        XCTAssertGreaterThanOrEqual(page.retrievedAt, started)
    }

    func testTitleAndInactiveTemplateDoNotMakeAScriptRenderedPageReadable() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/directory"))
        let client = VyronWebClient(transport: VyronWebTestTransport { target in
            VyronWebResponse(url: target, mediaType: "text/html", body: Data("""
            <html><head><title>Public directory</title><script src="/directory.js"></script></head>
            <body><main id="directory"></main><template>Inactive directory entry</template></body></html>
            """.utf8))
        })
        do {
            _ = try await client.read(url: url)
            XCTFail("Expected the empty page shell to use rendered lookup")
        } catch {
            XCTAssertEqual(error as? VyronWebError, .unsupportedContent)
        }
    }

    func testVisibleHTMLFragmentDoesNotRequireABodyTag() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/directory"))
        let client = VyronWebClient(transport: VyronWebTestTransport { target in
            VyronWebResponse(url: target, mediaType: "text/html", body: Data("""
            <title>Public directory</title><template>Inactive directory entry</template>
            <article>Open today.</article>
            """.utf8))
        })
        let page = try await client.read(url: url)
        XCTAssertEqual(page.source.title, "Public directory")
        XCTAssertEqual(page.text, "Open today.")
    }

    func testReadCollectsUniqueSameSiteLinksUsingTheDocumentBase() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/start"))
        let client = VyronWebClient(transport: VyronWebTestTransport { target in
            VyronWebResponse(url: target, mediaType: "text/html", body: Data("""
            <head><base href='/docs/'><base href='https://external.example/'></head><body>
              <a data-href='/fake' title="href='/inside-an-attribute'" HREF="intro?q=a&amp;sort=1#start">Intro</a>
              <a href=intro?q=a&amp;sort=1#end>Intro again</a>
              <map><area href='https://EXAMPLE.com:443/help'></map>
              <a href='/start#same-page'>Top</a>
              <a href='https://other.example/offsite'>Offsite</a>
              <a href='http://example.com/insecure'>Insecure</a>
              <a href='/download' download>Download</a>
              <!-- <a href='/comment'>Comment</a> -->
              <script>const markup = "<a href='/script'>Script</a>";</script>
              <template><a href='/template'>Template</a></template>
              <p data-html="<a href='/quoted'>Quoted</a>">Published body</p>
            </body>
            """.utf8))
        })

        let page = try await client.read(url: url)

        XCTAssertEqual(page.links.map(\.absoluteString), [
            "https://example.com/docs/intro?q=a&sort=1",
            "https://example.com/help"
        ])
    }

    func testLinkLimitCountsOnlyUniqueSameSiteCandidates() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/start"))
        let limit = VyronWebPageLinks.maximumCount
        let client = VyronWebClient(transport: VyronWebTestTransport { target in
            let outbound = (0..<limit).map { "<a href='https://other.example/\($0)'>External</a>" }.joined()
            let inbound = (0..<(limit + 1)).map { "<a href='/page/\($0)'>Internal</a>" }.joined()
            return VyronWebResponse(url: target, mediaType: "text/html", body: Data((outbound + inbound).utf8))
        })

        let page = try await client.read(url: url)

        XCTAssertEqual(page.links.count, limit)
        XCTAssertEqual(page.links.first?.path, "/page/0")
        XCTAssertEqual(page.links.last?.path, "/page/\(limit - 1)")
    }

    func testReadingBoundsTextAndRejectsOversizedAndUnsupportedResponses() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/long"))
        let bounded = VyronWebClient(transport: VyronWebTestTransport { target in
            VyronWebResponse(url: target, mediaType: "text/plain", body: Data(String(repeating: "a", count: 30_000).utf8))
        })
        let boundedPage = try await bounded.read(url: url)
        XCTAssertEqual(boundedPage.text.count, 20_000)
        let oversized = VyronWebClient(transport: VyronWebTestTransport { target in
            VyronWebResponse(url: target, mediaType: "text/plain", body: Data(repeating: 65, count: 1_048_577))
        })
        do {
            _ = try await oversized.read(url: url)
            XCTFail("Expected size limit")
        } catch { XCTAssertEqual(error as? VyronWebError, .responseTooLarge) }
        let image = VyronWebClient(transport: VyronWebTestTransport { target in
            VyronWebResponse(url: target, mediaType: "image/png", body: Data())
        })
        do {
            _ = try await image.read(url: url)
            XCTFail("Expected unsupported content")
        } catch { XCTAssertEqual(error as? VyronWebError, .unsupportedContent) }
    }

    func testCancellationPreventsAStaleSearchResult() async throws {
        let client = VyronWebClient(transport: VyronWebTestTransport { url in
            withUnsafeCurrentTask { $0?.cancel() }
            return VyronWebResponse(url: url, mediaType: "text/html", body: Data("""
            <a class='result__a' href='https://example.com/'>Stale result</a>
            """.utf8))
        })
        let task = Task { try await client.search(query: "pharmacies") }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testUnsafeURLsAreRejectedBeforeTransport() async throws {
        let client = VyronWebClient(transport: VyronWebTestTransport { _ in
            XCTFail("Unsafe URL reached transport")
            throw VyronWebError.unavailable
        })
        for raw in [
            "http://example.com", "file:///tmp/private", "https://127.0.0.1", "https://[::1]",
            "https://2130706433", "https://0x7f000001", "https://localhost", "https://app.local",
            "https://user:password@example.com", "https://example.com:8443", "https://app.internal"
        ] {
            let url = try XCTUnwrap(URL(string: raw))
            do {
                _ = try await client.read(url: url)
                XCTFail("Expected unsafe URL: \(raw)")
            } catch { XCTAssertEqual(error as? VyronWebError, .unsafeURL, raw) }
        }
    }
}
