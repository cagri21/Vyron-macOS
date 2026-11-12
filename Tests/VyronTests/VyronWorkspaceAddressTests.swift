import Foundation
import XCTest
@testable import Vyron

final class VyronWorkspaceAddressTests: XCTestCase {
    func testExplicitWebAddressesPreservePathAndQuery() throws {
        let url = try website("https://example.com/docs?q=swift&lang=en#section")
        XCTAssertEqual(url.absoluteString, "https://example.com/docs?q=swift&lang=en#section")
        XCTAssertEqual(try website("http://example.com").scheme, "http")
    }

    func testBareDomainDefaultsToHTTPSAndKeepsPortAndPath() throws {
        let url = try website("example.com:8443/docs?q=swift")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "example.com")
        XCTAssertEqual(url.port, 8443)
        XCTAssertEqual(url.path, "/docs")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "swift")
    }

    func testBareLoopbackDefaultsToHTTP() throws {
        for address in ["localhost:3000", "127.0.0.1:8080/path", "[::1]:8000", "app.localhost:3000"] {
            let url = try website(address)
            XCTAssertEqual(url.scheme, "http", address)
            XCTAssertNotEqual(url.host, "duckduckgo.com", address)
        }
    }

    func testSearchTermsAreEncodedAsOneQueryValue() throws {
        let terms = "Swift 6 actor & Sendable + examples #guide"
        let url = try website(terms)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "duckduckgo.com")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: terms)])
        XCTAssertNil(components.fragment)
    }

    func testPlainWordAndUnicodeSearchAreSearchQueries() throws {
        for value in ["swift", "İstanbul hava durumu", "приклад Swift"] {
            let url = try website(value)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.host, "duckduckgo.com")
            XCTAssertEqual(components.queryItems?.first?.value, value)
        }
    }

    func testUnsupportedSchemesCredentialsAndEmptyInputAreInvalid() {
        for value in [
            "", "  ", "javascript:alert(1)", "data:text/html,hello", "file:///tmp/example",
            "mailto:user@example.com", "about:blank", "https://user:secret@example.com",
            "user:secret@example.com", "https://", "https://example.com:70000", "one\ntwo"
        ] {
            XCTAssertEqual(VyronWorkspaceAddress.resolve(value), .invalid, value)
        }
    }

    func testNavigationPolicyAllowsOnlyCredentialFreeWebURLs() throws {
        for value in ["https://example.com", "http://localhost:3000", "https://example.com/download"] {
            XCTAssertTrue(VyronWorkspaceAddress.isAllowedWebsite(try XCTUnwrap(URL(string: value))), value)
        }
        for value in ["javascript:alert(1)", "file:///tmp/file", "https://user@example.com", "https://example.com:0"] {
            XCTAssertFalse(VyronWorkspaceAddress.isAllowedWebsite(try XCTUnwrap(URL(string: value))), value)
        }
    }

    private func website(_ address: String) throws -> URL {
        let resolution = VyronWorkspaceAddress.resolve(address)
        guard case .website(let location) = resolution else {
            XCTFail("Expected a website or encoded search for \(address)")
            throw CocoaError(.coderInvalidValue)
        }
        return location.url
    }
}
