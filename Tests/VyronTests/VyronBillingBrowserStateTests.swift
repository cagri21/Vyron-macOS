import Foundation
import WebKit
import XCTest
@testable import Vyron

@MainActor
final class VyronBillingBrowserStateTests: XCTestCase {
    func testBrowserStartsWithoutARequestAndOnlyOpensTheOfficialDashboardOnAction() throws {
        let browser = VyronBillingBrowserModel()
        XCTAssertNil(browser.request)
        XCTAssertEqual(browser.state.phase, .idle)
        browser.open()
        let request = try XCTUnwrap(browser.request)
        XCTAssertEqual(request.url, VyronBillingDashboard.openAI)
        XCTAssertEqual(request.url.host, "platform.openai.com")
        XCTAssertNil(request.url.user)
        XCTAssertNil(request.url.password)
        XCTAssertNil(request.url.query)
        XCTAssertEqual(browser.state.phase, .loading)
        browser.committed(request.id, url: URL(string: "https://auth.openai.com/authorize?state=offline-test"))
        XCTAssertEqual(browser.state.host, "auth.openai.com")
        browser.finished(request.id)
        XCTAssertEqual(browser.state.phase, .ready)
    }

    func testReloadHasANewIdentityAndOldCompletionFailureOrSignInCannotOverrideIt() throws {
        let browser = VyronBillingBrowserModel()
        browser.open()
        let first = try XCTUnwrap(browser.request)
        browser.open()
        let second = try XCTUnwrap(browser.request)
        XCTAssertNotEqual(first.id, second.id)
        browser.committed(first.id, url: URL(string: "https://auth.openai.com/"))
        browser.finished(first.id)
        browser.failed(first.id)
        browser.requiresBrowser(first.id)
        XCTAssertEqual(browser.request, second)
        XCTAssertEqual(browser.state.phase, .loading)
        XCTAssertEqual(browser.state.host, "platform.openai.com")
        browser.failed(second.id)
        XCTAssertEqual(browser.state.phase, .failed)
        browser.finished(second.id)
        browser.loading(second.id)
        XCTAssertEqual(browser.state.phase, .failed)
        browser.open()
        XCTAssertEqual(browser.state.phase, .loading)
    }

    func testClosingRejectsAllLateCallbacksAndKeepsNoPageOrigin() throws {
        let browser = VyronBillingBrowserModel()
        browser.open()
        let request = try XCTUnwrap(browser.request)
        browser.close()
        browser.loading(request.id)
        browser.committed(request.id, url: request.url)
        browser.finished(request.id)
        browser.failed(request.id)
        browser.requiresBrowser(request.id)
        XCTAssertNil(browser.request)
        XCTAssertEqual(browser.state.phase, .idle)
        XCTAssertNil(browser.state.host)
    }

    func testExternalSignInStateCannotBeReplacedByCancelledNavigationCallbacks() throws {
        let browser = VyronBillingBrowserModel()
        browser.open()
        let request = try XCTUnwrap(browser.request)
        browser.requiresBrowser(request.id)
        browser.failed(request.id)
        browser.loading(request.id)
        browser.finished(request.id)
        browser.committed(request.id, url: URL(string: "https://auth.openai.com/"))
        XCTAssertEqual(browser.state.phase, .browserSignInRequired)
        browser.open()
        XCTAssertNotEqual(browser.request?.id, request.id)
        XCTAssertEqual(browser.state.phase, .loading)
    }

    func testWebKitPolicyCallbackIsAnActualDelegateImplementation() {
        let coordinator = VyronBillingWebCoordinator(browser: VyronBillingBrowserModel())
        // The Objective-C selector is WebKit's stable boundary; a nearly matching Swift method is not invoked.
        XCTAssertTrue(coordinator.responds(to: NSSelectorFromString(
            "webView:decidePolicyForNavigationAction:decisionHandler:"
        )))
        coordinator.begin(UUID())
        XCTAssertNotNil(coordinator.requestID)
        coordinator.detach()
        XCTAssertNil(coordinator.requestID)
    }
}
