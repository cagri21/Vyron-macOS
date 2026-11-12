import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronLocalAuthHTTPTests: XCTestCase {
    func testTransportRejectsRemoteHostsAlternatePortsQueriesAndUnsupportedRoutesBeforeSending() async throws {
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: "unexpected") }
        let transport = transport()
        for address in [
            "https://example.test/v1/session", "http://localhost:8327/v1/session",
            "http://127.0.0.1:8328/v1/session", "http://127.0.0.1:8327/v1/session?private=1",
            "http://127.0.0.1:8327/v1/session#fragment", "http://127.0.0.1:8327/other"
        ] {
            let request = URLRequest(url: try XCTUnwrap(URL(string: address)))
            do { _ = try await transport.data(for: request); XCTFail("The request must stay on the exact local API.") }
            catch { XCTAssertEqual(error as? VyronLocalAuthError, .invalidConfiguration) }
        }
        let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testTransportBoundsResponsesAndSanitizesFailuresWithoutRetries() async throws {
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in
            .init(body: String(repeating: "x", count: 65_537))
        }
        let transport = transport()
        let request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:8327/v1/session")))
        do { _ = try await transport.data(for: request); XCTFail("Oversized responses must be rejected.") }
        catch { XCTAssertEqual(error as? VyronLocalAuthError, .invalidResponse) }
        let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
        XCTAssertEqual(requests.count, 1)
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in
            throw NSError(domain: "PrivateTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: "PRIVATE_AUTH_TOKEN"])
        }
        do { _ = try await transport.data(for: request); XCTFail("Transport errors must be sanitized.") }
        catch {
            XCTAssertEqual(error as? VyronLocalAuthError, .unavailable)
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_AUTH_TOKEN"))
        }
    }

    func testCancellationDuringResponseStopsLocalRequest() async throws {
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: "{", holdOpen: true) }
        let transport = transport()
        let request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:8327/v1/session")))
        let pending = Task { try await transport.data(for: request) }
        try await VyronConnectionBalanceTestSupport.waitUntil {
            await VyronConnectionBalanceTestURLProtocol.state.requests.count == 1
        }
        pending.cancel()
        do { _ = try await pending.value; XCTFail("Cancellation must stop the response.") }
        catch is CancellationError {} catch { XCTFail("Expected cancellation.") }
        try await VyronConnectionBalanceTestSupport.waitUntil {
            await VyronConnectionBalanceTestURLProtocol.state.stopCount > 0
        }
    }

    func testRedirectPolicyNeverForwardsAnAuthorizedRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronConnectionBalanceTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let source = try XCTUnwrap(URL(string: "http://127.0.0.1:8327/v1/session"))
        let remote = try XCTUnwrap(URL(string: "https://example.test/collect"))
        let response = try XCTUnwrap(HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil))
        let task = session.dataTask(with: source) // Never resumed; only the shared delegate policy is exercised.
        var redirected = URLRequest(url: remote)
        redirected.setValue("Bearer offline-dummy-token", forHTTPHeaderField: "Authorization")
        let blocked = await withCheckedContinuation { continuation in
            ProviderRejectRedirects().urlSession(
                session, task: task, willPerformHTTPRedirection: response, newRequest: redirected
            ) { request in continuation.resume(returning: request == nil) }
        }
        XCTAssertTrue(blocked)
    }

    private func transport() -> VyronLocalAuthHTTPTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronConnectionBalanceTestURLProtocol.self]
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "example.test", "HTTPPort": 80]
        return VyronLocalAuthHTTPTransport(configuration: configuration)
    }
}
