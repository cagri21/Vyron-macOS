import Foundation
import XCTest
@testable import Vyron

final class VyronWorkspaceLibraryTests: XCTestCase {
    private var directory = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronWorkspaceLibraryTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testPageAndWebsitePersistWithoutChangingOtherFiles() throws {
        let sentinel = directory.appendingPathComponent("history.json")
        try Data("unrelated history".utf8).write(to: sentinel)
        let storage = directory.appendingPathComponent("WorkspaceLibrary", isDirectory: true)
        let model = VyronWorkspaceLibraryModel(directory: storage)
        let page = VyronWorkspacePage(title: " Notes ", body: "# A local page\nPrivate notes.")
        XCTAssertTrue(model.savePage(page))
        XCTAssertTrue(model.addLink(title: "Developer", address: "https://developer.apple.com/account"))
        let link = try XCTUnwrap(model.links.first)
        XCTAssertTrue(model.recordLink(link))

        let reloaded = VyronWorkspaceLibraryModel(directory: storage)
        XCTAssertNil(reloaded.errorMessage)
        XCTAssertEqual(reloaded.pages.first?.id, page.id)
        XCTAssertEqual(reloaded.pages.first?.title, "Notes")
        XCTAssertEqual(reloaded.pages.first?.body, page.body)
        XCTAssertEqual(reloaded.links, model.links)
        XCTAssertEqual(reloaded.recents, model.recents)
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "unrelated history")
    }

    @MainActor
    func testOpeningSameFileDeduplicatesAndMovesItToFront() throws {
        let model = VyronWorkspaceLibraryModel(directory: directory)
        let first = directory.appendingPathComponent("First.pdf")
        let second = directory.appendingPathComponent("Second.txt")
        try Data().write(to: first)
        try Data().write(to: second)
        XCTAssertTrue(model.recordFile(first))
        XCTAssertTrue(model.recordFile(second))
        XCTAssertTrue(model.recordFile(first))
        XCTAssertEqual(model.recents.count, 2)
        XCTAssertEqual(model.recents.first?.url, first)
        XCTAssertEqual(model.recents.first?.kind, .file)
    }

    @MainActor
    func testRecentListIsBoundedWithoutDiscardingPages() {
        let model = VyronWorkspaceLibraryModel(directory: directory)
        for index in 0..<25 {
            XCTAssertTrue(model.savePage(VyronWorkspacePage(title: "Page \(index)")))
        }
        XCTAssertEqual(model.pages.count, 25)
        XCTAssertEqual(model.recents.count, 20)
        XCTAssertEqual(model.recents.first?.title, "Page 24")
    }

    @MainActor
    func testUpdatingPageKeepsIdentityAndRefreshesRecentTitle() throws {
        let model = VyronWorkspaceLibraryModel(directory: directory)
        var page = VyronWorkspacePage(title: "Draft", body: "First version")
        XCTAssertTrue(model.savePage(page))
        page.title = "Finished"
        page.body = "Revised text"
        XCTAssertTrue(model.savePage(page))
        XCTAssertEqual(model.pages.count, 1)
        XCTAssertEqual(model.pages.first?.id, page.id)
        XCTAssertEqual(model.pages.first?.body, "Revised text")
        XCTAssertEqual(model.recents.count, 1)
        XCTAssertEqual(model.recents.first?.title, "Finished")
        XCTAssertEqual(model.recents.first?.kind, .page)
        let restored = VyronWorkspaceLibraryModel(directory: directory)
        XCTAssertEqual(restored.recents, model.recents)
        XCTAssertNil(restored.errorMessage)
    }

    @MainActor
    func testLinkValidationRejectsOtherSchemesAndCredentials() {
        let model = VyronWorkspaceLibraryModel(directory: directory)
        for value in ["file:///tmp/page", "javascript:alert(1)", "https://user:secret@example.com", "example.com"] {
            XCTAssertFalse(model.addLink(title: "Invalid", address: value))
            XCTAssertNotNil(model.errorMessage)
        }
        XCTAssertTrue(model.links.isEmpty)
        XCTAssertTrue(model.addLink(title: "", address: " https://example.com/docs "))
        XCTAssertEqual(model.links.first?.title, "example.com")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testRemovingPagePersistsRemovalAndKeepsOtherPages() throws {
        let model = VyronWorkspaceLibraryModel(directory: directory)
        let removed = VyronWorkspacePage(title: "Remove")
        let retained = VyronWorkspacePage(title: "Keep")
        XCTAssertTrue(model.savePage(removed))
        XCTAssertTrue(model.savePage(retained))
        XCTAssertTrue(model.removePage(removed.id))
        XCTAssertEqual(model.pages.map(\.id), [retained.id])
        XCTAssertEqual(model.recents.count, 1)
        XCTAssertEqual(model.recents.first?.id, "page:\(retained.id.uuidString)")
        let reloaded = VyronWorkspaceLibraryModel(directory: directory)
        XCTAssertEqual(reloaded.pages.map(\.id), [retained.id])
        XCTAssertEqual(reloaded.recents, model.recents)
    }

    @MainActor
    func testDuplicateLinkUpdatesTitleAndRemovingLinkAlsoRemovesItsRecent() throws {
        let model = VyronWorkspaceLibraryModel(directory: directory)
        XCTAssertTrue(model.addLink(title: "Old", address: "https://example.com"))
        let link = try XCTUnwrap(model.links.first)
        XCTAssertTrue(model.recordLink(link))
        XCTAssertTrue(model.addLink(title: "New", address: "https://example.com"))
        XCTAssertEqual(model.links.count, 1)
        XCTAssertEqual(model.links.first?.id, link.id)
        XCTAssertEqual(model.recents.first?.title, "New")
        XCTAssertTrue(model.removeLink(link.id))
        XCTAssertTrue(model.links.isEmpty)
        XCTAssertTrue(model.recents.isEmpty)
    }

    @MainActor
    func testCorruptManifestIsPreservedAndBlocksWritesUntilSuccessfulReload() throws {
        let manifest = directory.appendingPathComponent("library.json")
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: manifest)
        let model = VyronWorkspaceLibraryModel(directory: directory)
        XCTAssertNotNil(model.errorMessage)
        model.errorMessage = nil
        XCTAssertFalse(model.savePage(VyronWorkspacePage(title: "Must not overwrite")))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try Data(contentsOf: manifest), corrupt)
        XCTAssertTrue(model.pages.isEmpty)

        try FileManager.default.removeItem(at: manifest)
        XCTAssertTrue(model.reload())
        XCTAssertTrue(model.savePage(VyronWorkspacePage(title: "Recovered")))
        XCTAssertEqual(model.pages.count, 1)
    }

    @MainActor
    func testWriteFailureRetainsPublishedStateAndAllowsRetry() throws {
        let model = VyronWorkspaceLibraryModel(directory: directory)
        XCTAssertTrue(model.savePage(VyronWorkspacePage(title: "Saved")))
        let manifest = directory.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        XCTAssertFalse(model.savePage(VyronWorkspacePage(title: "Not saved")))
        XCTAssertEqual(model.pages.map(\.title), ["Saved"])
        XCTAssertNotNil(model.errorMessage)
        try FileManager.default.removeItem(at: manifest)
        XCTAssertTrue(model.savePage(VyronWorkspacePage(title: "Retry")))
        XCTAssertEqual(model.pages.count, 2)
    }

    @MainActor
    func testManifestSymlinkIsRejectedWithoutChangingTarget() throws {
        let target = directory.appendingPathComponent("other.json")
        let data = Data("do not overwrite".utf8)
        try data.write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("library.json"), withDestinationURL: target
        )
        let model = VyronWorkspaceLibraryModel(directory: directory)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.addLink(title: "Denied", address: "https://example.com"))
        XCTAssertEqual(try Data(contentsOf: target), data)
    }

    @MainActor
    func testMissingFileDoesNotCreateARecentRecord() {
        let model = VyronWorkspaceLibraryModel(directory: directory)
        XCTAssertFalse(model.recordFile(directory.appendingPathComponent("missing.pdf")))
        XCTAssertTrue(model.recents.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testOversizedPageDoesNotReplaceItsSavedVersion() {
        let model = VyronWorkspaceLibraryModel(directory: directory)
        var page = VyronWorkspacePage(title: "Saved", body: "Original text")
        XCTAssertTrue(model.savePage(page))
        page.body = String(repeating: "a", count: VyronWorkspaceLibraryLimits.pageBodyBytes + 1)
        XCTAssertFalse(model.savePage(page))
        XCTAssertEqual(model.pages.first?.body, "Original text")
        XCTAssertNotNil(model.errorMessage)
    }
}
