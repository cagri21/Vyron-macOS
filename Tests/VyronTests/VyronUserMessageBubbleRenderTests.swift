import AppKit
import SwiftUI
import XCTest
import VyronModelDomain
@testable import Vyron

@MainActor
final class VyronUserMessageBubbleRenderTests: XCTestCase {
    func testSentImageIsSquareAndSharesTheBubbleTrailingEdge() throws {
        let content = "What's in this image?"
        let plain = ChatMessage(role: .user, content: content)
        let message = ChatMessage(role: .user, content: content, images: [try VyronScreenshotTestImage.attachment()])

        for width: CGFloat in [568, 260] {
            let baseline = try render(plain, width: width)
            let rendered = try render(message, width: width)
            XCTAssertEqual(rendered.height - baseline.height, (80 + 8) * 2)

            let bitmap = NSBitmapImageRep(cgImage: rendered)
            let centerY = (8 + 40) * 2
            let background = try XCTUnwrap(bitmap.colorAt(x: 0, y: centerY)?.usingColorSpace(.sRGB))
            let imageColumns = (0..<bitmap.pixelsWide).filter { x in
                guard let color = bitmap.colorAt(x: x, y: centerY)?.usingColorSpace(.sRGB) else { return false }
                return abs(color.redComponent - background.redComponent) > 0.03
            }
            let trailingEdge = bitmap.pixelsWide - 8 * 2
            XCTAssertEqual(imageColumns.first, trailingEdge - 80 * 2)
            XCTAssertEqual(imageColumns.last, trailingEdge - 1)
        }
    }

    func testCapturePlainAndClarificationMessages() async throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_USER_MESSAGE_BUBBLES"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_USER_MESSAGE_BUBBLES=1 for offscreen message bubble verification.")
        }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/user-message-bubbles", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let plain = ChatMessage(
            role: .user,
            content: "I want to paste a screenshot from the clipboard into the chat and ask Vyron about it. "
                + "Please keep the original image available in the conversation."
        )
        let answer = VyronClarificationAnswer(
            question: "Which chat should I fix for pasting Penpot from Finder?",
            answer: "The Vyron app’s chat"
        )
        var clarification = ChatMessage(role: .user, content: "\(answer.question)\n\(answer.answer)")
        clarification.clarificationAnswers = [answer]
        _ = try capture(plain, width: 568, to: directory.appendingPathComponent("plain.png"))
        let regular = try capture(clarification, width: 408, to: directory.appendingPathComponent("clarification.png"))
        let narrow = try capture(clarification, width: 260, to: directory.appendingPathComponent("narrow.png"))

        XCTAssertGreaterThan(narrow.height, regular.height, "Long questions should wrap on narrow layouts.")
    }

    private func capture(_ message: ChatMessage, width: CGFloat, to destination: URL) throws -> CGImage {
        let image = try render(message, width: width)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: destination, options: .atomic)
        return image
    }

    private func render(_ message: ChatMessage, width: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: VyronConversationMessageView(
            message: message,
            isStreaming: false,
            clarificationAnswers: message.clarificationAnswers ?? []
        )
        .padding(8)
        .frame(width: width)
        .background(Palette.canvas)
        .environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw XCTSkip("BLOCKED: offscreen ImageRenderer is unavailable.")
        }
        XCTAssertEqual(image.width, Int(width * renderer.scale))
        return image
    }
}
