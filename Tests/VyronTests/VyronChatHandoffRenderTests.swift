import AppKit
import SwiftUI
import XCTest
import VyronCore
import VyronLocalization
@testable import Vyron

/// Opt-in captures of the production chooser without opening an app, window, or provider connection.
@MainActor
final class VyronChatHandoffRenderTests: XCTestCase {
    func testCaptureHandoffChooserInEverySupportedLanguage() throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_CHAT_HANDOFF"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_CHAT_HANDOFF=1 for offscreen handoff verification.")
        }
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let presentation = try fixture(test)
        let originalMessages = test.model.selectedConversation?.messages
        let defaults = UserDefaults.standard
        let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for language in [VyronLanguage.english, .turkish, .ukrainian] {
            var arguments = previousArguments
            arguments[VyronLocalizationDefaultsKey.language.rawValue] = language.rawValue
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            let hosting = NSHostingView(rootView: VyronChatHandoffSheet(presentation: presentation)
                .environmentObject(test.model)
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.colorScheme, .dark)
            )
            hosting.appearance = NSAppearance(named: .darkAqua)
            hosting.frame = CGRect(x: 0, y: 0, width: VyronChatHandoffStyle.width, height: 1)
            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
                throw XCTSkip("BLOCKED: NSHostingView has no offscreen fitting size; no app/window fallback permitted.")
            }
            hosting.setFrameSize(size)
            hosting.layoutSubtreeIfNeeded()
            let editors = textEditors(in: hosting)
            guard let editor = editors.first(where: { $0.string == presentation.initialRequest }) else {
                throw XCTSkip(
                    "BLOCKED: offscreen NSHostingView did not materialize the native request editor; "
                        + "a partial SwiftUI snapshot does not verify the complete chooser."
                )
            }
            XCTAssertGreaterThan(editor.visibleRect.height, 0, "The actual native editor must participate in layout.")
            guard let editorBitmap = editor.bitmapImageRepForCachingDisplay(in: editor.visibleRect) else {
                throw XCTSkip("BLOCKED: native request-editor bitmap capture is unavailable offscreen.")
            }
            editor.cacheDisplay(in: editor.visibleRect, to: editorBitmap)
            guard let editorImage = editorBitmap.cgImage, try hasForegroundContent(editorImage) else {
                throw XCTSkip("BLOCKED: offscreen native request editor did not paint its text; visual QA is incomplete.")
            }
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw XCTSkip("BLOCKED: native offscreen bitmap capture unavailable; no app/window fallback permitted.")
            }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage)
            let suffix = language == .english ? "" : "-" + language.rawValue
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("chat-handoff" + suffix + ".png"), options: .atomic)
            XCTAssertEqual(size.width, VyronChatHandoffStyle.width, accuracy: 1)
            XCTAssertGreaterThan(size.height, 325)
            XCTAssertLessThan(size.height, 760, "The translated chooser must fit a standard desktop window.")
            guard try hasForegroundContent(image) else {
                throw XCTSkip("BLOCKED: native offscreen capture omitted chooser content; no app/window fallback permitted.")
            }
        }
        XCTAssertEqual(test.model.selectedConversationID, presentation.sourceID)
        XCTAssertEqual(test.model.selectedConversation?.messages, originalMessages)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertTrue(test.model.composer.draft.isEmpty)
    }

    private func fixture(_ test: VyronQueueTestHarness) throws -> VyronChatHandoffPresentation {
        let project = test.directory.appendingPathComponent("iOS-Study", isDirectory: true)
        let website = project.appendingPathComponent("Website", isDirectory: true)
        let articles = project.appendingPathComponent("Articles", isDirectory: true)
        for folder in [website, articles] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        XCTAssertTrue(test.model.changeSidebar {
            try $0.updateProject(path: project.path, name: "iOS-Study", sourceFolders: [website.path, articles.path])
        })
        var source = Conversation(title: "AI model bits and local inference", workspacePath: nil)
        source.mode = ComposerMode.chat.rawValue
        source.messages = [
            ChatMessage(role: "user", content: "Explain 4-bit model quantization and memory requirements."),
            ChatMessage(role: "assistant", content: "Quantization stores model weights with less numerical precision.")
        ]
        var destination = Conversation(title: "Devopedia articles and AI lessons", workspacePath: website.path)
        destination.projectPath = project.path
        destination.mode = ComposerMode.agent.rawValue
        destination.messages = [ChatMessage(role: "user", content: "Maintain the published learning articles.")]
        test.model.conversations = [source, destination]
        test.model.selectedConversationID = source.id
        test.model.composer.mode = .chat
        test.model.registerSidebarConversation(source.id)
        test.model.registerSidebarConversation(destination.id)
        return VyronChatHandoffPresentation(
            sourceID: source.id,
            initialRequest: "Write a beginner-friendly article explaining AI model bits, quantization, "
                + "memory, and running large models locally. Publish it using this project's established workflow.",
            destination: VyronChatHandoffSelection(
                projectPath: project.path, workspacePath: website.path, conversationID: destination.id
            )
        )
    }

    private func hasForegroundContent(_ image: CGImage) throws -> Bool {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        try pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        var lightPixels = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2]) > 450 { lightPixels += 1 }
        }
        return lightPixels > max(200, image.width * image.height / 1_000)
    }

    private func textEditors(in view: NSView) -> [NSTextView] {
        let current = (view as? NSTextView).map { [$0] } ?? []
        return current + view.subviews.flatMap { textEditors(in: $0) }
    }
}
