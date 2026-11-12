import AppKit
import Foundation
import UniformTypeIdentifiers
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronScreenshotDropLoaderTests: XCTestCase {
    func testRawImageDropNormalizesPixelsWithoutAFileURL() async throws {
        let provider = provider(data: try VyronScreenshotTestImage.jpeg(), type: .jpeg)
        XCTAssertTrue(VyronScreenshotDropLoader.accepts([provider], remainingCapacity: 4))

        let images = try await VyronScreenshotDropLoader(providers: [provider]).load()

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.name, VyronScreenshotText.droppedImage)
        XCTAssertEqual(images.first?.mimeType, "image/png")
        XCTAssertTrue(images.first?.data.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
    }

    func testLocalImageFileDropReadsItsPixelsAndKeepsItsName() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let url = test.directory.appendingPathComponent("Screen.jpg")
        try VyronScreenshotTestImage.jpeg().write(to: url)
        let provider = provider(data: url.dataRepresentation, type: .fileURL, name: url.lastPathComponent)

        let images = try await VyronScreenshotDropLoader(providers: [provider]).load()

        XCTAssertEqual(images.map(\.name), [url.lastPathComponent])
        XCTAssertEqual(images.first?.mimeType, "image/png")
    }

    func testTextLinksAndNonImageFilesAreRejectedBeforeLoading() {
        let text = provider(data: Data("hello".utf8), type: .plainText)
        let link = provider(data: Data("https://example.invalid/image.png".utf8), type: .url)
        let file = provider(data: Data(), type: .fileURL, name: "Notes.txt")

        for candidate in [text, link, file] {
            XCTAssertFalse(VyronScreenshotDropLoader.accepts([candidate], remainingCapacity: 4))
        }
        XCTAssertFalse(VyronScreenshotDropLoader.accepts([], remainingCapacity: 4))
    }

    func testMixedDropAndCapacityOverflowAreRejectedAtomically() throws {
        let image = provider(data: try VyronScreenshotTestImage.jpeg(), type: .jpeg)
        let text = provider(data: Data("hello".utf8), type: .plainText)

        XCTAssertFalse(VyronScreenshotDropLoader.accepts([image, text], remainingCapacity: 4))
        XCTAssertFalse(VyronScreenshotDropLoader.accepts([image, image], remainingCapacity: 1))
        XCTAssertFalse(VyronScreenshotDropLoader.accepts([image], remainingCapacity: 0))
    }

    func testRemoteURLAdvertisedAsAFileURLIsRejected() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid/image.png"))
        let provider = provider(data: url.dataRepresentation, type: .fileURL, name: "image.png")
        do {
            _ = try await VyronScreenshotDropLoader(providers: [provider]).load()
            XCTFail("A remote URL was accepted as a local image.")
        } catch {
            XCTAssertTrue(error is VyronScreenshotImportError)
        }
    }

    func testAdvertisedPixelsTakePriorityOverAnUnusableURLRepresentation() async throws {
        let provider = provider(data: try VyronScreenshotTestImage.jpeg(), type: .jpeg, name: "Browser image")
        let url = try XCTUnwrap(URL(string: "https://example.invalid/image.png"))
        let urlData = url.dataRepresentation
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier, visibility: .all
        ) { completion in
            completion(urlData, nil)
            return nil
        }

        let images = try await VyronScreenshotDropLoader(providers: [provider]).load()

        XCTAssertEqual(images.map(\.name), ["Browser image"])
        XCTAssertEqual(images.first?.mimeType, "image/png")
    }

    func testInvalidImageDropPreservesExistingDraftAndRetrySucceeds() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let existing = try VyronScreenshotTestImage.attachment()
        test.model.composerAttachments.screenshotDraft.images = [existing]
        let valid = provider(data: try VyronScreenshotTestImage.jpeg(), type: .jpeg, name: "Dropped.jpg")
        let invalid = provider(data: Data("invalid image".utf8), type: .png)
        let invalidLoader = VyronScreenshotDropLoader(providers: [valid, invalid])
        test.model.loadScreenshotImages { try await invalidLoader.load() }
        try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images, [existing])
        XCTAssertNotNil(test.model.errorMessage)

        let validLoader = VyronScreenshotDropLoader(providers: [valid])
        test.model.loadScreenshotImages { try await validLoader.load() }
        try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images.map(\.name), [existing.name, "Dropped.jpg"])
        XCTAssertNil(test.model.errorMessage)
    }

    func testOversizedRawImageIsRejectedBeforeNormalization() async throws {
        let data = Data(repeating: 0, count: VyronScreenshotLimits.maximumImportBytes + 1)
        let provider = provider(data: data, type: .png)
        do {
            _ = try await VyronScreenshotDropLoader(providers: [provider]).load()
            XCTFail("An oversized dropped image was accepted.")
        } catch let error as VyronScreenshotImportError {
            guard case .tooLarge = error else { return XCTFail("Expected the image size error.") }
        }
    }

    func testChangingConversationCancelsDropWithoutAttachingItsLateResult() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = provider(data: try VyronScreenshotTestImage.jpeg(), type: .jpeg)
        let loader = VyronScreenshotDropLoader(providers: [provider])
        test.model.loadScreenshotImages { try await loader.load() }
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.isLoading)

        test.model.newConversation()
        for _ in 0..<30 { await Task.yield() }

        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.images.isEmpty)
        XCTAssertFalse(test.model.composerAttachments.screenshotDraft.isLoading)
        XCTAssertNil(test.model.composerAttachments.screenshotImportTask)
        XCTAssertNil(test.model.errorMessage)
    }

    func testCancelingAnUnfinishedProviderReadDoesNotWaitForTheProvider() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { _ in
            Progress(totalUnitCount: 1)
        }
        let loader = VyronScreenshotDropLoader(providers: [provider])
        var finished = false
        var canceled = false
        let task = Task {
            defer { finished = true }
            do {
                _ = try await loader.load()
            } catch is CancellationError {
                canceled = true
            } catch {
                XCTFail("Expected cancellation, received \(error).")
            }
        }
        for _ in 0..<10 { await Task.yield() }
        task.cancel()
        try await test.waitUntil { finished }
        XCTAssertTrue(canceled)
    }

    private func provider(data: Data, type: UTType, name: String? = nil) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}
