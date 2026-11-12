import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronConnectionBalancePolicyTests: XCTestCase {
    func testOnlyCanonicalKnownHTTPSProviderBasesAreFetchable() {
        for endpoint in [
            "https://api.deepseek.com", "https://api.deepseek.com/", "https://api.deepseek.com/v1",
            "https://API.DEEPSEEK.COM:443/v1/"
        ] {
            let support = VyronConnectionBalancePolicy.support(for: VyronConnectionBalanceTestSupport.profile(endpoint))
            XCTAssertEqual(support, .deepSeek, endpoint)
            XCTAssertTrue(support.canFetch)
        }
        for endpoint in ["https://openrouter.ai/api/v1", "https://openrouter.ai:443/api/v1/"] {
            let support = VyronConnectionBalancePolicy.support(for: VyronConnectionBalanceTestSupport.profile(endpoint))
            XCTAssertEqual(support, .openRouter, endpoint)
            XCTAssertTrue(support.canFetch)
        }
        for endpoint in ["https://api.openai.com", "https://api.openai.com/v1/"] {
            let support = VyronConnectionBalancePolicy.support(for: VyronConnectionBalanceTestSupport.profile(endpoint))
            XCTAssertEqual(support, .dashboardOnly)
            XCTAssertFalse(support.canFetch)
        }
    }

    func testHostConfusionUntrustedPathsCredentialsAndWrongKindNeverFetch() async {
        let endpoints = [
            "http://api.deepseek.com/v1", "https://api.deepseek.com:8443/v1",
            "https://api.deepseek.com.evil.example/v1", "https://api.deepseek.com./v1",
            "https://api.deepseek.com@evil.example/v1", "https://user:password@api.deepseek.com/v1",
            "https://api.deepseek.com/v1?token=not-a-key", "https://api.deepseek.com/v1#fragment",
            "https://api.deepseek.com/v1/../user", "https://api.deepseek.com/%76%31",
            "https://api.deepseek.com/v1/%2f", "https://api.deepseek.com/user/balance",
            "https://openrouter.ai/api/v1/key", "https://openrouter.ai/api/v1/credits",
            "https://openrouter.ai/v1", "https://openrouter.ai/api//v1",
            "https://api.openai.com/v1/organization", "https://unknown.example/v1"
        ]
        await VyronConnectionBalanceTestURLProtocol.state.configure()
        let client = VyronConnectionBalanceTestSupport.client()
        for endpoint in endpoints {
            let profile = VyronConnectionBalanceTestSupport.profile(endpoint)
            XCTAssertEqual(VyronConnectionBalancePolicy.support(for: profile), .unsupported, endpoint)
            do {
                _ = try await client.fetchBalance(for: profile, apiKey: VyronConnectionBalanceTestSupport.key)
                XCTFail("An unsupported profile must not contact a provider.")
            } catch {
                XCTAssertEqual(error as? VyronConnectionBalanceError, .unsupported)
            }
        }
        var wrongKind = VyronConnectionBalanceTestSupport.profile()
        wrongKind.kind = .ollama
        XCTAssertEqual(VyronConnectionBalancePolicy.support(for: wrongKind), .unsupported)
        let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testLocalDashboardAndMissingKeyPathsDoNotMakeHTTPRequests() async {
        await VyronConnectionBalanceTestURLProtocol.state.configure()
        let client = VyronConnectionBalanceTestSupport.client()
        for endpoint in [
            "http://127.0.0.1:11434", "http://localhost:1234/v1", "https://api.openai.com/v1",
            "https://unknown.example/v1"
        ] {
            let profile = VyronConnectionBalanceTestSupport.profile(endpoint)
            XCTAssertFalse(VyronConnectionBalancePolicy.support(for: profile).canFetch)
            do {
                _ = try await client.fetchBalance(for: profile, apiKey: "")
                XCTFail("A non-fetchable profile must not request credentials or transport.")
            } catch {
                XCTAssertEqual(error as? VyronConnectionBalanceError, .unsupported)
            }
        }
        for key in ["", " \n ", "bad\nkey", "two words", String(repeating: "a", count: 8_193)] {
            do {
                _ = try await client.fetchBalance(for: VyronConnectionBalanceTestSupport.profile(), apiKey: key)
                XCTFail("An absent or invalid key must stop before transport.")
            } catch {
                XCTAssertEqual(error as? VyronConnectionBalanceError, .missingKey)
            }
        }
        let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
        XCTAssertTrue(requests.isEmpty)
    }
}
