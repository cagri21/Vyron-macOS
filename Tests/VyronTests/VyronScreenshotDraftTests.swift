import AppKit
import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronScreenshotDraftTests: XCTestCase {
    func testClipboardPNGAndTIFFBecomeDraftAttachments() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let draft = "Describe this screenshot."
        test.model.composer.draft = draft
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: VyronScreenshotTestImage.jpeg()))

        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            let data = try XCTUnwrap(bitmap.representation(using: type == .png ? .png : .tiff, properties: [:]))
            XCTAssertTrue(test.model.pasteScreenshotImage(reportEmptyClipboard: false) { $0 == type ? data : nil })
            try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }
        }

        let images = test.model.composerAttachments.screenshotDraft.images
        XCTAssertEqual(images.map(\.name), Array(repeating: VyronScreenshotText.pastedImage, count: 2))
        XCTAssertEqual(images.map(\.mimeType), ["image/png", "image/png"])
        XCTAssertEqual(test.model.composer.draft, draft)
        XCTAssertNil(test.model.errorMessage)
    }

    func testTextClipboardFallsThroughToStandardPaste() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let model = test.model
        let readText: (NSPasteboard.PasteboardType) -> Data? = { $0 == .string ? Data("Pasted text".utf8) : nil }

        XCTAssertFalse(model.pasteScreenshotImage(reportEmptyClipboard: false, readData: readText))
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.composerAttachments.screenshotImportTask)

        XCTAssertFalse(model.pasteScreenshotImage(readData: readText))
        XCTAssertEqual(model.errorMessage, VyronScreenshotText.clipboardEmpty)
    }

    func testImageImportPreservesPlanAndAllowsModeChoiceBeforeFirstMessage() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider, capabilities: ["vision", "tools"])
        test.model.composer.mode = .plan
        test.model.attachCapturedScreenshot(try VyronScreenshotTestImage.jpeg(), name: "Plan.jpg")
        XCTAssertFalse(test.model.canSelectComposerMode(.chat))
        try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }

        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images.map(\.name), ["Plan.jpg"])
        XCTAssertTrue(test.model.canSelectComposerMode(.chat))
        test.model.selectComposerMode(.chat)
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images.map(\.name), ["Plan.jpg"])
        XCTAssertTrue(test.model.canSelectComposerMode(.plan))
        test.model.selectComposerMode(.plan)
        XCTAssertTrue(test.model.canSend)
    }

    func testLateCaptureCannotAttachToNewConversationEvenIfPickerIsReopened() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.model.openScreenshotPicker()
        let oldGeneration = test.model.composerAttachments.screenshotCaptureGeneration
        test.model.newConversation()
        test.model.openScreenshotPicker()

        test.model.completeScreenshotCapture(
            try VyronScreenshotTestImage.jpeg(), name: "Old Simulator.jpg", generation: oldGeneration
        )

        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.images.isEmpty)
        XCTAssertFalse(test.model.composerAttachments.screenshotDraft.isLoading)
        XCTAssertNil(test.model.composerAttachments.screenshotImportTask)
        XCTAssertTrue(test.model.composerAttachments.showScreenshotPicker)
    }

    func testOversizedImagePromptKeepsDraftAndAttachments() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider, capabilities: ["vision"])
        test.model.composerAttachments.screenshotDraft.images = try (0..<4).map {
            try VyronScreenshotTestImage.attachment(name: "Screen \($0).jpg")
        }
        let images = test.model.composerAttachments.screenshotDraft.images
        let prompt = String(repeating: "x", count: 10_000)
        test.model.composer.draft = prompt

        test.model.send()

        XCTAssertEqual(test.model.composer.draft, prompt)
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images, images)
        XCTAssertTrue(test.model.messages.isEmpty)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertNotNil(test.model.errorMessage)
    }

    func testNewConversationCancelsImportAndRejectsItsStaleResult() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let data = try VyronScreenshotTestImage.jpeg()
        let generation = test.model.composerAttachments.screenshotDraft.generation
        test.model.attachCapturedScreenshot(data, name: "Old.jpg")
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.isLoading)
        test.model.newConversation()
        test.model.composer.draft = "A different conversation."
        for _ in 0..<30 { await Task.yield() }

        XCTAssertNotEqual(test.model.composerAttachments.screenshotDraft.generation, generation)
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.images.isEmpty)
        XCTAssertFalse(test.model.composerAttachments.screenshotDraft.isLoading)
        XCTAssertNil(test.model.composerAttachments.screenshotImportTask)
        XCTAssertNil(test.model.errorMessage)
        XCTAssertEqual(test.model.composer.draft, "A different conversation.")
    }

    func testMultiImageImportIsAtomicAndRetryWorksAfterInvalidFile() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let good = test.directory.appendingPathComponent("Good.jpg")
        let bad = test.directory.appendingPathComponent("Bad.png")
        try VyronScreenshotTestImage.jpeg().write(to: good)
        try Data("not an image".utf8).write(to: bad)
        test.model.importScreenshotImages([good, bad])
        try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.images.isEmpty)
        XCTAssertNotNil(test.model.errorMessage)

        test.model.importScreenshotImages([good])
        try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images.map(\.name), ["Good.jpg"])
        XCTAssertNil(test.model.errorMessage)
        let id = try XCTUnwrap(test.model.composerAttachments.screenshotDraft.images.first?.id)
        test.model.removeScreenshot(id)
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.images.isEmpty)
    }

    func testImportLimitDoesNotDiscardExistingAttachments() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let image = try VyronScreenshotTestImage.attachment()
        test.model.composerAttachments.screenshotDraft.images = [image]
        let urls = (0..<VyronImageAttachment.maximumCount).map {
            test.directory.appendingPathComponent("Image\($0).jpg")
        }
        test.model.importScreenshotImages(urls)

        XCTAssertFalse(test.model.composerAttachments.screenshotDraft.isLoading)
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images, [image])
        XCTAssertNotNil(test.model.errorMessage)
    }
}
