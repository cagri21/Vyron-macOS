import Foundation
import XCTest
@testable import Vyron

final class VyronBillingNavigationTests: XCTestCase {
    func testOfficialBillingAndOpenAISignInRemainEmbedded() {
        for address in [
            "https://platform.openai.com/settings/organization/billing/overview",
            "https://auth.openai.com/authorize?state=offline-test",
            "https://auth0.openai.com/", "https://OPENAI.com:443/", "about:blank"
        ] {
            XCTAssertEqual(VyronBillingNavigationPolicy.decision(for: URL(string: address), isMainFrame: true), .allow)
        }
    }

    func testOtherSignInProvidersRequireTheOfficialBrowserFallbackInsteadOfLoadingInsideSettings() {
        for address in [
            "https://accounts.google.com/", "https://login.microsoftonline.com/",
            "https://platform.openai.com.evil.test/", "https://fake-openai.com/", "https://example.test/"
        ] {
            XCTAssertEqual(
                VyronBillingNavigationPolicy.decision(for: URL(string: address), isMainFrame: true), .browserRequired
            )
        }
    }

    func testUnsafeSchemesCredentialsAndPortsAreBlocked() {
        for address in [
            "http://platform.openai.com/", "file:///private/file", "javascript:alert(1)",
            "data:text/html,test", "https://user:password@platform.openai.com/", "https://openai.com:8443/"
        ] {
            for isMain in [true, false] {
                XCTAssertEqual(VyronBillingNavigationPolicy.decision(for: URL(string: address), isMainFrame: isMain), .block)
            }
        }
        XCTAssertEqual(VyronBillingNavigationPolicy.decision(for: nil, isMainFrame: true), .block)
    }

    func testNormalSecureSubresourcesCanLoadWithoutChangingTheTrustedTopLevel() {
        XCTAssertEqual(VyronBillingNavigationPolicy.decision(
            for: URL(string: "https://challenges.cloudflare.com/"), isMainFrame: false
        ), .allow)
    }
}
