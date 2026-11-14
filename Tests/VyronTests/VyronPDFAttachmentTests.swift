import AppKit
import CoreGraphics
import CoreText
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronPDFAttachmentTests: XCTestCase {
    private let text = "Text from the local PDF."

    func testComposerRendersRedPDFAndBlueImageTypes() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider)
        let model = test.model
        model.composer.draft = "Review these attachments."
        let pdf = try await VyronPDFAttachmentLoader().load(document(lines: [text]), name: "Project brief.pdf")
        model.composerAttachments.pdfs = [pdf]
        model.composerAttachments.screenshotDraft.images = [try VyronScreenshotTestImage.attachment()]
        model.composerAttachments.files = [
            VyronFileAttachment(info: .init(name: "Interview.mp3", kind: .audio, duration: 18), text: nil)
        ]
        let content = VyronComposer()
            .environmentObject(model)
            .environment(\.colorScheme, .dark)
            .frame(width: 504)
            .background(Palette.canvas)
        let hosting = NSHostingView(rootView: content)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(x: 0, y: 0, width: 504, height: 1)
        for _ in 0..<4 {
            hosting.layoutSubtreeIfNeeded()
            await Task.yield()
            hosting.setFrameSize(hosting.fittingSize)
        }
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw XCTSkip("BLOCKED: native offscreen composer capture is unavailable.")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/mixed-attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("composer.png"), options: .atomic)

        XCTAssertTrue(bitmapContainsTypeAccent(bitmap, red: false, horizontalRange: 15..<58))
        XCTAssertTrue(bitmapContainsTypeAccent(bitmap, red: true, horizontalRange: 176..<222))
    }

    func testPDFDropUsesPDFTypeAndProducesFirstPagePreview() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let localFile = test.directory.appendingPathComponent("Reference.PDF")
        try document(lines: [text]).write(to: localFile)

        let data = localFile.dataRepresentation
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        let result = try await VyronComposerDropLoader(providers: [provider]).load()
        let pdf = try XCTUnwrap(result.pdfs.first)

        XCTAssertEqual(result.pdfs.count, 1)
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertTrue(result.folders.isEmpty)
        XCTAssertEqual(pdf.preview.name, "Reference.PDF")
        XCTAssertEqual(pdf.text, text)
        XCTAssertNotNil(pdf.preview.imageData.flatMap { NSImage(data: $0) })
    }

    func testPDFOnlySendSuppliesTextAndPersistsLocalPreview() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronScreenshotTestProvider()
        test.select(test.profile(), provider: provider)
        let file = test.directory.appendingPathComponent("Reference.pdf")
        try document(lines: [text]).write(to: file)
        test.model.importPDFAttachments([file])
        XCTAssertTrue(test.model.composerAttachments.isImporting)
        XCTAssertFalse(test.model.canSend)
        try await test.waitUntil { !test.model.composerAttachments.isImporting }
        XCTAssertTrue(test.model.canSend)

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let requests = await provider.receivedMessages

        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests.first?.contains {
            $0.content.contains(text) && ($0.images ?? []).isEmpty && $0.pdfPreviews == nil
        } == true)
        XCTAssertTrue(test.model.composerAttachments.pdfs.isEmpty)
        let data = try Data(contentsOf: test.directory.appendingPathComponent("conversations.json"))
        let saved = try JSONDecoder().decode([Conversation].self, from: data)
        let message = try XCTUnwrap(saved.first?.messages.first)
        XCTAssertEqual(message.pdfPreviews?.first?.name, "Reference.pdf")
        XCTAssertNotNil(message.pdfPreviews?.first?.imageData)
        XCTAssertTrue(saved.first?.contextByMessageID?[message.id.uuidString]?.contains(text) == true)
    }

    func testMixedFileSelectionSendsPDFImageAudioAndTextTogether() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronScreenshotTestProvider()
        test.select(test.profile(), provider: provider, capabilities: ["vision"])
        test.model.skillContextLoader = { _ in .empty }
        test.model.computerWork.automaticRequestRouting = true
        let urls = try writeMixedFiles(in: test.directory)

        test.model.importFileAttachments(urls)
        try await test.waitUntil { !test.model.composerAttachments.isImporting }

        let attachments = test.model.composerAttachments
        XCTAssertNil(test.model.errorMessage)
        XCTAssertEqual(attachments.pdfs.map(\.preview.name), ["Reference.pdf"])
        XCTAssertEqual(attachments.screenshotDraft.images.map(\.name), ["Diagram.png"])
        XCTAssertEqual(Set(attachments.files.map(\.info.name)), ["Clip.mp3", "Data.csv"])
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let allRequests = await provider.receivedMessages
        let request = try XCTUnwrap(allRequests.first)
        let sent = try XCTUnwrap(request.first { $0.content.contains(text) })
        XCTAssertEqual(sent.images?.map(\.name), ["Diagram.png"])
        XCTAssertTrue(sent.content.contains("Clip.mp3"))
        XCTAssertTrue(sent.content.contains("Only metadata was supplied."))
        XCTAssertTrue(sent.content.contains("north,12"))
        XCTAssertNil(sent.pdfPreviews)
        XCTAssertNil(sent.fileAttachments)
        XCTAssertFalse(attachments.hasDrafts)
        let stored = try test.model.historyStore.load()
        let visible = try XCTUnwrap(stored.first?.messages.first)
        XCTAssertEqual(visible.pdfPreviews?.map(\.name), ["Reference.pdf"])
        XCTAssertEqual(Set(visible.fileAttachments?.map(\.name) ?? []), ["Clip.mp3", "Data.csv"])
        XCTAssertEqual(visible.fileAttachments?.first(where: { $0.kind == .audio })?.hasTranscript, false)

        test.model.composer.draft = "Compare the attached files again."
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let followUp = await provider.receivedMessages.last
        XCTAssertTrue(followUp?.contains { $0.content.contains("north,12") && $0.content.contains("Clip.mp3") } == true)
    }

    func testMixedFinderDropKeepsAllThreeFileTypes() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let urls = try writeMixedFiles(in: test.directory)
        let items = urls.prefix(3).map { url in
            let item = NSItemProvider()
            let data = url.dataRepresentation
            item.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
            return item
        }
        let result = try await VyronComposerDropLoader(providers: items).load()
        XCTAssertEqual(result.pdfs.map(\.preview.name), ["Reference.pdf"])
        XCTAssertEqual(result.images.map(\.name), ["Diagram.png"])
        XCTAssertEqual(result.files.map(\.info.name), ["Clip.mp3"])
        XCTAssertGreaterThan(result.files.first?.info.duration ?? 0, 0)
    }

    private func writeMixedFiles(in directory: URL) throws -> [URL] {
        let pdf = directory.appendingPathComponent("Reference.pdf")
        let image = directory.appendingPathComponent("Diagram.png")
        let audio = directory.appendingPathComponent("Clip.mp3")
        let textFile = directory.appendingPathComponent("Data.csv")
        try document(lines: [text]).write(to: pdf)
        let pixels = try VyronScreenshotTestImage.jpeg()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: pixels))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: image)
        try VyronAudioAttachmentTestFixture.mp3().write(to: audio)
        try Data("region,count\nnorth,12\n".utf8).write(to: textFile)
        return [pdf, image, audio, textFile]
    }

    func testPDFExtractionHonorsPageLimitAndRejectsPagesWithoutText() async throws {
        let loader = VyronPDFAttachmentLoader()
        let firstPages = Array(repeating: text, count: VyronPDFAttachmentLimits.maximumExtractedPages)
        let limitedPDF = try document(lines: firstPages + ["Excluded page content"])
        let pdf = try await loader.load(limitedPDF, name: "Limited.pdf")
        XCTAssertTrue(pdf.isTruncated)
        XCTAssertTrue(pdf.text.contains(text))
        XCTAssertFalse(pdf.text.contains("Excluded page content"))
        XCTAssertLessThanOrEqual(pdf.text.utf8.count, VyronPDFAttachmentLimits.maximumTextBytes)

        let noTextPDF = try document(lines: [""])
        do {
            _ = try await loader.load(noTextPDF, name: "Scan.pdf")
            XCTFail("A PDF with no selectable text was attached for analysis.")
        } catch let error as VyronPDFAttachmentError {
            guard case .noText = error else { return XCTFail(error.localizedDescription) }
        }
    }

    func testPDFOnlyPlanIncludesMultipleDocumentsBeyondPriorConversationBudget() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronWorkImageTestProvider()
        test.select(test.profile(), provider: provider, capabilities: ["tools"])
        test.model.skillContextLoader = { _ in .empty }
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .plan
        let first = test.directory.appendingPathComponent("First.pdf")
        let second = test.directory.appendingPathComponent("Second.pdf")
        let filler = Array(
            repeating: "Every attached document should keep a reference excerpt when the model begins its response.",
            count: 29
        )
        try document(lines: ["First document marker."] + filler).write(to: first)
        try document(lines: ["Second document marker."] + filler).write(to: second)
        test.model.importPDFAttachments([first, second])
        try await test.waitUntil { !test.model.composerAttachments.isImporting }
        let pdfs = test.model.composerAttachments.pdfs
        XCTAssertEqual(pdfs.count, 2)
        XCTAssertGreaterThan(pdfs.reduce(0) { $0 + $1.text.utf8.count }, 4_096)

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let requests = await provider.requests
        let modes = await provider.requestedModes
        XCTAssertEqual(modes, [.plan])
        let content = try XCTUnwrap(requests.first).map(\.content).joined(separator: "\n")
        XCTAssertTrue(content.contains("First document marker."))
        XCTAssertTrue(content.contains("Second document marker."))
    }

    private func document(lines: [String]) throws -> Data {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var page = CGRect(x: 0, y: 0, width: 480, height: 640)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &page, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 9, nil)
        for text in lines {
            context.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            ))
            context.textPosition = CGPoint(x: 24, y: 600)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private func bitmapContainsTypeAccent(
        _ bitmap: NSBitmapImageRep,
        red: Bool,
        horizontalRange: Range<Int>
    ) -> Bool {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        for y in 0..<bitmap.pixelsHigh {
            for pixel in horizontalRange {
                let x = Int(CGFloat(pixel) * scale)
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if red, color.redComponent > 0.65, color.greenComponent < 0.45, color.blueComponent < 0.45 {
                    return true
                }
                if !red, color.blueComponent > 0.65, color.redComponent < 0.45, color.greenComponent > 0.4 {
                    return true
                }
            }
        }
        return false
    }
}
