import AppKit
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Vyron

@MainActor
final class VyronComposerDropLoaderTests: XCTestCase {
    func testFolderWithPeriodInNameLoadsAsFolder() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let folder = test.directory.appendingPathComponent("Project.v2", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("Nested folder evidence.\n".utf8).write(to: folder.appendingPathComponent("Notes.txt"))
        let item = provider(data: folder.dataRepresentation, type: .fileURL)
        item.suggestedName = folder.lastPathComponent

        XCTAssertTrue(VyronComposerDropLoader.accepts([item]))
        let result = try await VyronComposerDropLoader(providers: [item]).load()

        XCTAssertTrue(result.images.isEmpty)
        XCTAssertEqual(result.folders.map(\.name), ["Project.v2"])
        XCTAssertTrue(result.folders.first?.context.contains("Nested folder evidence.") == true)
    }

    func testMixedFolderAndRawImageDropLoadsBoth() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let folder = provider(data: test.project.dataRepresentation, type: .fileURL)
        let image = provider(data: try VyronScreenshotTestImage.jpeg(), type: .jpeg)

        let result = try await VyronComposerDropLoader(providers: [folder, image]).load()

        XCTAssertEqual(result.folders.map(\.name), ["Project"])
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images.first?.mimeType, "image/png")
    }

    func testTextAndWebLinksAreRejectedBeforeLoading() {
        let text = provider(data: Data("hello".utf8), type: .plainText)
        let link = provider(data: Data("https://example.invalid".utf8), type: .url)

        XCTAssertFalse(VyronComposerDropLoader.accepts([text]))
        XCTAssertFalse(VyronComposerDropLoader.accepts([link]))
        XCTAssertFalse(VyronComposerDropLoader.accepts([]))
        XCTAssertFalse(VyronComposerDropLoader.accepts([text, link]))
    }

    func testInvalidMixedDropPreservesExistingFoldersAndRetrySucceeds() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let existing = try await VyronFolderAttachmentLoader().load(test.project)
        test.model.composerAttachments.folderAttachmentDraft.folders = [existing]
        let valid = provider(data: test.project.dataRepresentation, type: .fileURL)
        let invalid = provider(data: Data("not an image".utf8), type: .png)

        XCTAssertTrue(test.model.acceptComposerDrop([valid, invalid]))
        try await test.waitUntil { !test.model.composerAttachments.isImporting }
        XCTAssertEqual(test.model.composerAttachments.folderAttachmentDraft.folders, [existing])
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.images.isEmpty)
        XCTAssertNotNil(test.model.errorMessage)

        XCTAssertTrue(test.model.acceptComposerDrop([valid]))
        try await test.waitUntil { !test.model.composerAttachments.isImporting }
        XCTAssertEqual(test.model.composerAttachments.folderAttachmentDraft.folders.count, 2)
        XCTAssertNil(test.model.errorMessage)
    }

    func testRemoteAddressAdvertisedAsFileURLIsRejected() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/folder"))
        let item = provider(data: url.dataRepresentation, type: .fileURL)

        do {
            _ = try await VyronComposerDropLoader(providers: [item]).load()
            XCTFail("A remote address was accepted as a local folder.")
        } catch {
            XCTAssertTrue(error is VyronFolderAttachmentError)
        }
    }

    private func provider(data: Data, type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}
