import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronRenderedWebConversationTests: XCTestCase {
    func testScopedReaderRejectsOtherOriginsBeforeStartingNavigation() async throws {
        let seed = try XCTUnwrap(URL(string: "https://example.com/"))
        let external = try XCTUnwrap(URL(string: "https://external.example.com/guide"))
        let reader = VyronWorkspaceBrowserReader(websiteScope: try VyronWebsiteScope(seedURL: seed))

        do {
            _ = try await reader.read(url: external)
            XCTFail("Expected a site-wide browser read to reject a different origin")
        } catch {
            XCTAssertEqual(error as? VyronWebError, .unsafeURL)
            XCTAssertNil(reader.webView.url)
        }
    }

    func testRenderedTabUsesATemporaryBrowserUntilManualReload() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/directory"))
        let reader = VyronWorkspaceBrowserReader()
        let browser = VyronWorkspaceBrowserModel(url: url, renderedReader: reader)
        XCTAssertFalse(reader.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertNil(browser.request)
        XCTAssertTrue(browser.isLoading)

        let reading = Task { try await browser.readRenderedPage() }
        reading.cancel()
        do {
            _ = try await reading.value
            XCTFail("Expected a cancelled browser read")
        } catch is CancellationError {
            XCTAssertFalse(browser.isLoading)
            XCTAssertNil(browser.request)
        }

        browser.reload()
        XCTAssertNil(browser.renderedReader)
        XCTAssertEqual(browser.request?.command, .navigate(VyronWorkspaceBrowserLocation(url: url)))
    }

    func testUnreadablePublicPageContinuesTheOriginalReplyWithRenderedEvidence() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        await test.access.fail(with: .unsupportedContent)
        let url = try XCTUnwrap(URL(string: "https://example.com/directory"))
        let renderedURL = try XCTUnwrap(URL(string: "https://example.com/directory?view=hours"))
        var browserURLs: [URL] = []
        var browserResponses: [VyronResponseIdentity] = []
        test.model.readRenderedWebPage = { url, response, scope in
            browserURLs.append(url)
            browserResponses.append(response)
            XCTAssertNil(scope)
            let source = VyronWebSource(title: "Rendered directory", url: renderedURL, excerpt: "")
            return VyronWebPage(source: source, text: "RENDERED_DIRECTORY_MARKER: The directory closes at 18:00.")
        }
        test.model.composer.draft = "Analyze \(url.absoluteString)"

        test.model.send()
        let originalResponse = try XCTUnwrap(test.model.foregroundRun.activeResponse)
        try await test.finishReply()

        let searches = await test.access.searchQueries
        let directReads = await test.access.readURLs
        let requests = await test.provider.receivedMessages
        XCTAssertTrue(searches.isEmpty)
        XCTAssertEqual(directReads, [url])
        XCTAssertEqual(browserURLs, [url])
        XCTAssertEqual(browserResponses, [originalResponse])
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests.first?.contains { message in
            message.content.contains("RENDERED_DIRECTORY_MARKER")
                && message.content.contains(renderedURL.absoluteString)
        } == true)
        XCTAssertEqual(test.model.messages.last?.id, originalResponse.messageID)
        XCTAssertEqual(test.model.messages.last?.content, "Web answer 1 grounded in supplied evidence.")
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        XCTAssertNil(test.model.errorMessage)
    }

    func testBrowserOpensOnlyAfterUnreadablePublicHTTPSLookup() async throws {
        for (prompt, failure) in [
            ("Analyze https://example.com/directory", VyronWebError.unavailable),
            ("Analyze http://example.com/directory", .unsupportedContent),
            ("Find pharmacies in Istanbul", .unsupportedContent)
        ] {
            let test = try VyronWebConversationHarness()
            defer { test.cleanUp() }
            await test.access.fail(with: failure)
            test.model.readRenderedWebPage = { url, _, _ in
                XCTFail("Unexpected browser read for \(url) after \(prompt)")
                throw failure
            }
            test.model.composer.draft = prompt

            test.model.send()
            try await test.finishReply()

            let requests = await test.provider.receivedMessages
            XCTAssertTrue(requests.isEmpty, prompt)
            XCTAssertEqual(test.model.messages.last?.activity?.state, .failed, prompt)
        }
    }

    func testBrowserReadFailureEndsTheOriginalReplyWithoutModelInference() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        await test.access.fail(with: .unsupportedContent)
        var browserWasOpened = false
        test.model.readRenderedWebPage = { _, _, _ in
            browserWasOpened = true
            throw VyronWebError.unavailable
        }
        test.model.composer.draft = "Analyze https://example.com/directory"

        test.model.send()
        let originalResponse = try XCTUnwrap(test.model.foregroundRun.activeResponse)
        try await test.finishReply()

        let requests = await test.provider.receivedMessages
        XCTAssertTrue(browserWasOpened)
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(test.model.messages.last?.id, originalResponse.messageID)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        let failureText = VyronWebError.unavailable.localizedDescription
        XCTAssertTrue(test.model.messages.last?.content.contains(failureText) == true)
    }

    func testStoppedBrowserReadCannotAffectItsReplacementReply() async throws {
        let test = try VyronWebConversationHarness()
        defer { test.cleanUp() }
        await test.access.fail(with: .unsupportedContent)
        var browserRead: CheckedContinuation<VyronWebPage, Error>?
        var browserReturned = false
        test.model.readRenderedWebPage = { url, _, _ in
            guard browserRead == nil else {
                XCTFail("The readable replacement URL opened the browser: \(url)")
                throw VyronWebError.unsupportedContent
            }
            let page = try await withCheckedThrowingContinuation { browserRead = $0 }
            browserReturned = true
            return page
        }
        defer { browserRead?.resume(throwing: CancellationError()) }
        let url = try XCTUnwrap(URL(string: "https://example.com/directory"))
        test.model.composer.draft = "Analyze \(url.absoluteString)"
        test.model.send()
        try await test.base.waitUntil { browserRead != nil }
        let stoppedID = try XCTUnwrap(test.model.messages.last?.id)

        test.model.stopGeneration()
        let stoppedActivity = test.model.messages.last?.activity
        XCTAssertEqual(stoppedActivity?.state, .stopped)
        await test.access.fail(with: nil)
        test.model.composer.draft = "Analyze https://example.com/pharmacy"
        test.model.send()
        try await test.finishReply()
        let replacement = try XCTUnwrap(test.model.messages.last)
        XCTAssertNotEqual(replacement.id, stoppedID)
        XCTAssertEqual(replacement.activity?.state, .completed)

        let pendingRead = try XCTUnwrap(browserRead)
        browserRead = nil
        let source = VyronWebSource(title: "Old directory", url: url, excerpt: "")
        pendingRead.resume(returning: VyronWebPage(source: source, text: "STALE_BROWSER_MARKER"))
        try await test.base.waitUntil { browserReturned }
        for _ in 0..<20 { await Task.yield() }

        let requests = await test.provider.receivedMessages
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests.first?.contains { $0.content.contains("WEB_EVIDENCE_MARKER") } == true)
        XCTAssertEqual(test.model.messages.first { $0.id == stoppedID }?.activity, stoppedActivity)
        XCTAssertEqual(test.model.messages.last, replacement)
    }
}
