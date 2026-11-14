import AppKit
import XCTest
@testable import Vyron

@MainActor
final class VyronComposerPasteTests: XCTestCase {
    func testFileURLPasteAttachesApplicationAndKeepsDraftText() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let application = test.directory.appendingPathComponent("Demo Tool.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: application.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        let draft = "Open this application."
        test.model.composer.draft = draft

        XCTAssertTrue(test.model.pasteComposerAttachments(readFileURLs: { [application] }) { _ in
            XCTFail("An application URL should take precedence over an image representation.")
            return nil
        })
        try await test.waitUntil { !test.model.composerAttachments.isImporting }

        XCTAssertEqual(test.model.composerAttachments.applications.map(\.path), [application.path])
        XCTAssertTrue(test.model.composerAttachments.folderAttachmentDraft.folders.isEmpty)
        XCTAssertEqual(test.model.composer.draft, draft)
        XCTAssertNil(test.model.errorMessage)
    }

    func testCopiedPathTextUsesStandardPaste() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }

        XCTAssertFalse(test.model.pasteComposerAttachments(readFileURLs: { [] }) { type in
            type == .string ? Data("/Applications/Demo Tool.app".utf8) : nil
        })

        XCTAssertFalse(test.model.composerAttachments.hasDrafts)
        XCTAssertFalse(test.model.composerAttachments.isImporting)
        XCTAssertNil(test.model.errorMessage)
    }
}
