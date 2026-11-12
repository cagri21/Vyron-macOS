import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronWorkspaceTabsPresentationTests: XCTestCase {
    func testSubmittingAddressReusesHomeTabAndCreatesBrowserState() throws {
        try withPresentation { presentation, _ in
            let homeID = try XCTUnwrap(presentation.newTab())
            XCTAssertTrue(presentation.submitAddress("example.com/docs"))
            XCTAssertEqual(presentation.tabs.selectedID, homeID)
            XCTAssertEqual(presentation.tabs.tabs.count, 2)
            XCTAssertEqual(presentation.tabs.selectedTab.kind, .website)
            let browser = try XCTUnwrap(presentation.browsers[homeID])
            XCTAssertEqual(browser.url?.absoluteString, "https://example.com/docs")
            XCTAssertTrue(browser.isLoading)
            XCTAssertNotNil(browser.request)
            XCTAssertTrue(presentation.submitAddress("example.org/updated"))
            XCTAssertTrue(presentation.browsers[homeID] === browser)
            XCTAssertEqual(browser.url?.absoluteString, "https://example.org/updated")
            XCTAssertEqual(presentation.tabs.tabs.count, 2)
        }
    }

    func testSwitchingTabsRetainsIndependentBrowserHistoryState() throws {
        try withPresentation { presentation, _ in
            let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
            let secondURL = try XCTUnwrap(URL(string: "https://example.org/second"))
            let firstID = try XCTUnwrap(presentation.openWebsite(firstURL))
            let first = try XCTUnwrap(presentation.browsers[firstID])
            first.finished(first.generationID, snapshot: VyronWorkspaceBrowserSnapshot(
                url: firstURL, title: "First page", canGoBack: true, canGoForward: false
            ))
            let firstRequestID = first.request?.id
            let secondID = try XCTUnwrap(presentation.openWebsite(secondURL))
            let second = try XCTUnwrap(presentation.browsers[secondID])
            XCTAssertFalse(first === second)
            XCTAssertTrue(presentation.selectedBrowser === second)
            XCTAssertTrue(presentation.tabs.select(firstID))
            XCTAssertTrue(presentation.selectedBrowser === first)
            XCTAssertEqual(first.request?.id, firstRequestID)
            XCTAssertEqual(first.displayTitle, "First page")
            XCTAssertTrue(first.canGoBack)
            XCTAssertEqual(second.url, secondURL)
            XCTAssertFalse(second.canGoBack)
        }
    }

    func testReopeningSavedPageKeepsItsUnsavedDraftSession() throws {
        try withPresentation { presentation, _ in
            let page = VyronWorkspacePage(title: "Saved title", body: "Saved body")
            XCTAssertTrue(presentation.library.savePage(page))
            let id = try XCTUnwrap(presentation.openPage(page))
            let session = try XCTUnwrap(presentation.pageSessions[id])
            session.draft.title = "Draft title"
            session.draft.body = "Unsaved text"
            presentation.selectConversation()
            XCTAssertEqual(presentation.openPage(page), id)
            XCTAssertTrue(presentation.pageSessions[id] === session)
            XCTAssertEqual(session.draft.title, "Draft title")
            XCTAssertEqual(session.draft.body, "Unsaved text")
            XCTAssertTrue(session.hasChanges)
            XCTAssertEqual(presentation.tabs.tabs.count, 2)
            XCTAssertEqual(presentation.library.pages.first?.body, "Saved body")
        }
    }

    func testReopeningSavedPageKeepsLiveDraftTitleInTabHeader() throws {
        try withPresentation { presentation, _ in
            let page = VyronWorkspacePage(title: "Saved title", body: "Saved body")
            XCTAssertTrue(presentation.library.savePage(page))
            let id = try XCTUnwrap(presentation.openPage(page))
            let session = try XCTUnwrap(presentation.pageSessions[id])
            session.draft.title = "Unsaved title"
            presentation.selectConversation()
            XCTAssertEqual(presentation.openPage(page), id)
            XCTAssertEqual(presentation.tabs.selectedTab.title, "Unsaved title")
            XCTAssertEqual(session.draft.title, "Unsaved title")
            XCTAssertEqual(presentation.library.pages.first?.title, "Saved title")
        }
    }

    func testNewBlankPageBecomesSavedOnlyAfterSuccessfulSave() throws {
        try withPresentation { presentation, directory in
            presentation.newPage()
            let id = presentation.tabs.selectedID
            let session = try XCTUnwrap(presentation.pageSessions[id])
            XCTAssertFalse(session.isSaved)
            XCTAssertFalse(session.hasChanges)
            XCTAssertTrue(presentation.library.pages.isEmpty)
            XCTAssertTrue(presentation.savePage(in: id))
            XCTAssertTrue(session.isSaved)
            XCTAssertFalse(session.hasChanges)
            let reloaded = VyronWorkspaceLibraryModel(directory: directory)
            XCTAssertEqual(reloaded.pages.first?.id, session.draft.id)
            XCTAssertEqual(reloaded.pages.first?.body, "")
        }
    }

    func testCancellingCloseKeepsDirtyTabAndDraft() throws {
        try withPresentation { presentation, _ in
            presentation.newPage()
            let id = presentation.tabs.selectedID
            let session = try XCTUnwrap(presentation.pageSessions[id])
            session.draft.body = "Keep this draft"
            presentation.requestClose(id)
            XCTAssertEqual(presentation.pendingCloseID, id)
            XCTAssertTrue(presentation.tabs.tabs.contains { $0.id == id })
            presentation.pendingCloseID = nil
            XCTAssertEqual(presentation.tabs.selectedID, id)
            XCTAssertEqual(presentation.pageSessions[id]?.draft.body, "Keep this draft")
            XCTAssertTrue(session.hasChanges)
            XCTAssertTrue(presentation.library.pages.isEmpty)
        }
    }

    func testDiscardingCloseRemovesOnlyRequestedDraft() throws {
        try withPresentation { presentation, _ in
            presentation.newPage()
            let id = presentation.tabs.selectedID
            let session = try XCTUnwrap(presentation.pageSessions[id])
            session.draft.body = "Discard this draft"
            let otherID = try XCTUnwrap(presentation.newTab())
            presentation.requestClose(id)
            presentation.pendingCloseID = nil
            presentation.discardPendingClose(id)
            XCTAssertNil(presentation.pendingCloseID)
            XCTAssertNil(presentation.pageSessions[id])
            XCTAssertFalse(presentation.tabs.tabs.contains { $0.id == id })
            XCTAssertEqual(presentation.tabs.selectedID, otherID)
            XCTAssertTrue(presentation.library.pages.isEmpty)
        }
    }

    func testSavingPendingClosePersistsPageBeforeRemovingSession() throws {
        try withPresentation { presentation, directory in
            presentation.newPage()
            let id = presentation.tabs.selectedID
            let session = try XCTUnwrap(presentation.pageSessions[id])
            session.draft.title = "Persisted notes"
            session.draft.body = "Saved before closing"
            let pageID = session.draft.id
            presentation.requestClose(id)
            presentation.pendingCloseID = nil
            presentation.savePendingClose(id)
            XCTAssertNil(presentation.pendingCloseID)
            XCTAssertNil(presentation.pageSessions[id])
            XCTAssertFalse(presentation.tabs.tabs.contains { $0.id == id })
            let reloaded = VyronWorkspaceLibraryModel(directory: directory)
            XCTAssertEqual(reloaded.pages.first?.id, pageID)
            XCTAssertEqual(reloaded.pages.first?.body, "Saved before closing")
            XCTAssertEqual(reloaded.pages.first?.title, "Persisted notes")
        }
    }

    func testFailedPendingSaveKeepsTabDraftAndShowsSaveError() throws {
        try withPresentation { presentation, directory in
            presentation.newPage()
            let id = presentation.tabs.selectedID
            let session = try XCTUnwrap(presentation.pageSessions[id])
            session.draft.body = "Must remain recoverable"
            presentation.requestClose(id)
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("library.json"), withIntermediateDirectories: false
            )
            presentation.pendingCloseID = nil
            presentation.savePendingClose(id)
            XCTAssertNil(presentation.pendingCloseID)
            XCTAssertTrue(presentation.tabs.tabs.contains { $0.id == id })
            XCTAssertTrue(presentation.pageSessions[id] === session)
            XCTAssertEqual(session.draft.body, "Must remain recoverable")
            XCTAssertTrue(session.hasChanges)
            XCTAssertTrue(presentation.library.pages.isEmpty)
            XCTAssertNotNil(presentation.library.errorMessage)
            XCTAssertEqual(presentation.addressError, presentation.library.errorMessage)
        }
    }

    func testSavingPageMarksSessionCleanAndUpdatesTabTitle() throws {
        try withPresentation { presentation, _ in
            presentation.newPage()
            let id = presentation.tabs.selectedID
            let session = try XCTUnwrap(presentation.pageSessions[id])
            session.draft.title = "Saved title"
            session.draft.body = "Saved body"
            XCTAssertTrue(session.hasChanges)
            XCTAssertTrue(presentation.savePage(in: id))
            XCTAssertFalse(session.hasChanges)
            XCTAssertEqual(presentation.tabs.selectedTab.title, "Saved title")
            presentation.requestClose(id)
            XCTAssertNil(presentation.pendingCloseID)
            XCTAssertNil(presentation.pageSessions[id])
            XCTAssertEqual(presentation.library.pages.first?.body, "Saved body")
        }
    }

    func testDeletingCleanSavedPageClosesItsTabAndPersistsDeletion() throws {
        try withPresentation { presentation, directory in
            let page = VyronWorkspacePage(title: "Delete me", body: "Saved body")
            XCTAssertTrue(presentation.library.savePage(page))
            let id = try XCTUnwrap(presentation.openPage(page))
            XCTAssertTrue(presentation.canDeletePage(page))
            presentation.deletePage(page)
            XCTAssertTrue(presentation.library.pages.isEmpty)
            XCTAssertNil(presentation.pageSessions[id])
            XCTAssertFalse(presentation.tabs.tabs.contains { $0.id == id })
            XCTAssertTrue(VyronWorkspaceLibraryModel(directory: directory).pages.isEmpty)
        }
    }

    func testDeletingSavedPageIsBlockedWhileItsDraftIsDirty() throws {
        try withPresentation { presentation, directory in
            let page = VyronWorkspacePage(title: "Keep me", body: "Saved body")
            XCTAssertTrue(presentation.library.savePage(page))
            let id = try XCTUnwrap(presentation.openPage(page))
            let session = try XCTUnwrap(presentation.pageSessions[id])
            session.draft.body = "Unsaved body"
            XCTAssertFalse(presentation.canDeletePage(page))
            presentation.deletePage(page)
            XCTAssertEqual(presentation.library.pages.count, 1)
            XCTAssertTrue(presentation.pageSessions[id] === session)
            XCTAssertEqual(session.draft.body, "Unsaved body")
            XCTAssertTrue(presentation.tabs.tabs.contains { $0.id == id })
            XCTAssertEqual(VyronWorkspaceLibraryModel(directory: directory).pages.first?.body, "Saved body")
        }
    }

    func testBrowserPolicyMatchesAddressPolicyForDirectNavigation() throws {
        for address in [
            "https://example.com", "http://localhost:3000", "https://user:pass@example.com",
            "https://example.com:0", "https://example.com:70000", "file:///tmp/file", "javascript:alert(1)"
        ] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertEqual(
                VyronWorkspaceBrowserPolicy.allows(url), VyronWorkspaceAddress.isAllowedWebsite(url), address
            )
        }
    }

    private func withPresentation(_ action: (VyronWorkspaceTabsPresentation, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronWorkspaceTabsPresentationTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { XCTFail("Could not remove workspace tabs test storage: \(error)") }
        }
        let library = VyronWorkspaceLibraryModel(directory: directory)
        try action(VyronWorkspaceTabsPresentation(library: library), directory)
    }
}
