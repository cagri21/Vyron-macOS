import Foundation
import XCTest
@testable import Vyron

/// Exercises pure browser state and URL policy without instantiating WebKit or making requests.
@MainActor
final class VyronWorkspaceBrowserTests: XCTestCase {
    func testInitialRequestAndNavigationCommandsAreExplicitAndKeepHistoryAvailability() throws {
        let first = try url("https://example.com/start")
        let model = VyronWorkspaceBrowserModel(url: first)
        let initial = try XCTUnwrap(model.request)
        XCTAssertEqual(initial.command, .navigate(VyronWorkspaceBrowserLocation(url: first)))
        XCTAssertEqual(model.address, first.absoluteString)
        XCTAssertEqual(model.displayTitle, "example.com")
        XCTAssertTrue(model.isLoading)
        model.goBack()
        model.goForward()
        XCTAssertEqual(model.request, initial)

        model.finished(initial.id, snapshot: snapshot(first, title: "Start page", back: true, forward: true))
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.displayTitle, "Start page")
        model.goBack()
        let back = try XCTUnwrap(model.request)
        XCTAssertEqual(back.command, .back)
        XCTAssertNotEqual(back.id, initial.id)
        model.goForward()
        let forward = try XCTUnwrap(model.request)
        XCTAssertEqual(forward.command, .forward)
        XCTAssertNotEqual(forward.id, back.id)
        model.reload()
        XCTAssertEqual(model.request?.command, .reload)
    }

    func testNewNavigationRejectsStaleCompletionFailureAndCancellation() throws {
        let first = try url("https://example.com/first")
        let second = try url("https://example.com/second")
        let model = VyronWorkspaceBrowserModel(url: first)
        let stale = try XCTUnwrap(model.request?.id)
        model.navigate(to: second)
        let current = try XCTUnwrap(model.request?.id)

        model.finished(stale, snapshot: snapshot(first, title: "Stale title"))
        model.failed(stale, message: "Stale failure")
        model.cancelled(stale)

        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.address, second.absoluteString)
        XCTAssertEqual(model.displayTitle, "example.com")
        XCTAssertNil(model.errorMessage)
        model.finished(current, snapshot: snapshot(second, title: "Current title"))
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.displayTitle, "Current title")
    }

    func testStopInvalidatesCallbacksAndCancellationIsDistinctFromFailure() throws {
        let location = try url("https://example.com")
        let model = VyronWorkspaceBrowserModel(url: location)
        let initial = try XCTUnwrap(model.request?.id)
        model.stop()
        XCTAssertEqual(model.request?.command, .stop)
        XCTAssertFalse(model.isLoading)
        model.started(initial)
        model.failed(initial, message: "Cancelled request must not show an error")
        model.finished(initial, snapshot: snapshot(location, title: "Cancelled title"))
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertNotEqual(model.displayTitle, "Cancelled title")

        model.reload()
        let cancelled = try XCTUnwrap(model.request?.id)
        model.cancelled(cancelled)
        model.failed(cancelled, message: "Failure after cancellation")
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    func testFailureRemainsVisibleUntilRetryAndLateFinishCannotClearIt() throws {
        let location = try url("https://example.com/report")
        let model = VyronWorkspaceBrowserModel(url: location)
        let request = try XCTUnwrap(model.request)
        model.failed(request.id, message: "The content process stopped")
        model.failed(request.id, message: "A later WebKit cancellation must not replace the failure")
        model.finished(request.id, snapshot: snapshot(location, title: "Late completion"))
        XCTAssertEqual(model.errorMessage, "The content process stopped")
        XCTAssertFalse(model.isLoading)

        model.reload()
        let retry = try XCTUnwrap(model.request)
        XCTAssertNotEqual(retry.id, request.id)
        XCTAssertEqual(retry.command, .reload)
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.errorMessage)
        model.finished(retry.id, snapshot: snapshot(location, title: "Recovered"))
        XCTAssertEqual(model.displayTitle, "Recovered")
        XCTAssertFalse(model.isLoading)
    }

    func testPageNavigationAndRedirectRefreshAddressWithoutIssuingDuplicateCommand() throws {
        let initialURL = try url("https://example.com/start")
        let redirectURL = try url("https://example.org/destination")
        let model = VyronWorkspaceBrowserModel(url: initialURL)
        let initial = try XCTUnwrap(model.request)
        model.finished(initial.id, snapshot: snapshot(initialURL, title: "Start"))
        let pageNavigation = model.beginPageNavigation()
        XCTAssertEqual(model.request, initial)
        XCTAssertNotEqual(pageNavigation, initial.id)
        XCTAssertTrue(model.isLoading)
        model.updated(pageNavigation, snapshot: snapshot(redirectURL, title: nil, back: true))
        XCTAssertEqual(model.address, redirectURL.absoluteString)
        model.finished(pageNavigation, snapshot: snapshot(redirectURL, title: "Destination", back: true))
        XCTAssertEqual(model.displayTitle, "Destination")
        XCTAssertTrue(model.canGoBack)
        XCTAssertFalse(model.isLoading)
        let sameDocumentURL = try url("https://example.org/destination#details")
        model.updated(pageNavigation, snapshot: snapshot(sameDocumentURL, title: "Details", back: true))
        XCTAssertEqual(model.url, sameDocumentURL)
        XCTAssertEqual(model.displayTitle, "Details")
        XCTAssertEqual(model.request, initial)
        XCTAssertFalse(model.isLoading)
    }

    func testUnsafeAddressesAreRefusedWithoutReplacingExistingPageOrRequest() throws {
        let safe = try url("https://example.com")
        let model = VyronWorkspaceBrowserModel(url: safe)
        let initial = model.request
        for address in [
            "file:///tmp/private.txt", "javascript:alert(1)", "data:text/html,hello", "about:blank",
            "mailto:person@example.com", "https://user:password@example.com", "https://user@example.com"
        ] {
            let unsafe = try url(address)
            XCTAssertFalse(VyronWorkspaceBrowserPolicy.allows(unsafe))
            model.navigate(to: unsafe)
            XCTAssertEqual(model.request, initial)
            XCTAssertEqual(model.url, safe)
            XCTAssertEqual(model.errorMessage, VyronBrowserText.invalidAddress)
        }
        XCTAssertTrue(VyronWorkspaceBrowserPolicy.allows(try url("http://localhost:8080/path?q=one#two")))
        XCTAssertTrue(VyronWorkspaceBrowserPolicy.allows(try url("HTTPS://example.com/path")))
    }

    func testWebKitInternalSubframesDoNotWeakenTopLevelWebsitePolicy() throws {
        for address in [
            "about:blank", "about:srcdoc", "about:blank#embedded",
            "data:text/html,embedded", "blob:https://example.com/document-id", "blob:null/document-id"
        ] {
            let internalURL = try url(address)
            XCTAssertTrue(VyronWorkspaceBrowserPolicy.allowsNavigation(internalURL, isMainFrame: false), address)
            XCTAssertFalse(VyronWorkspaceBrowserPolicy.allowsNavigation(internalURL, isMainFrame: true), address)
            XCTAssertFalse(VyronWorkspaceBrowserPolicy.allows(internalURL), address)
        }
        for address in ["https://example.com/frame", "http://localhost:8080/frame"] {
            let website = try url(address)
            XCTAssertTrue(VyronWorkspaceBrowserPolicy.allowsNavigation(website, isMainFrame: true))
            XCTAssertTrue(VyronWorkspaceBrowserPolicy.allowsNavigation(website, isMainFrame: false))
        }
    }

    func testSubframesStillRejectFilesCustomSchemesScriptsAndCredentialURLs() throws {
        for address in [
            "file:///tmp/private.txt", "javascript:alert(1)", "custom-app:launch", "about:settings",
            "blob:file:///tmp/private.txt", "blob:javascript:alert(1)", "https://user:secret@example.com"
        ] {
            let rejected = try url(address)
            XCTAssertFalse(VyronWorkspaceBrowserPolicy.allowsNavigation(rejected, isMainFrame: false), address)
            XCTAssertFalse(VyronWorkspaceBrowserPolicy.allowsNavigation(rejected, isMainFrame: true), address)
        }
    }

    private func snapshot(
        _ url: URL,
        title: String?,
        back: Bool = false,
        forward: Bool = false
    ) -> VyronWorkspaceBrowserSnapshot {
        VyronWorkspaceBrowserSnapshot(url: url, title: title, canGoBack: back, canGoForward: forward)
    }

    private func url(_ address: String) throws -> URL {
        try XCTUnwrap(URL(string: address))
    }
}
