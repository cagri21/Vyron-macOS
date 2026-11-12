import AppKit
import SwiftUI
import XCTest
import VyronCore
import VyronDevelopment
@testable import Vyron

/// Opt-in visual evidence from the actual views; never starts an application, window or provider request.
@MainActor
final class VyronWorkspaceOverviewRenderTests: XCTestCase {
    func testCaptureActualOverviewAndDetachedWindows() throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_WORKSPACE_HEADER"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_WORKSPACE_HEADER=1 for isolated offscreen visual verification.")
        }
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/workspace-header", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let emptyOverview = try capture(
            VyronTaskOverviewView(),
            model: test.model,
            size: CGSize(width: 300, height: 400),
            to: directory.appendingPathComponent("overview-empty.png")
        )
        guard try hasForegroundContent(emptyOverview) else {
            throw XCTSkip(
                "BLOCKED: ImageRenderer omitted native scroll content; no application/window fallback permitted"
            )
        }
        let conversation = try populatedConversation()
        test.model.selectedConversationID = nil
        test.model.composer.mode = .agent
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id
        test.model.workspaceState.workspaceURL = URL(fileURLWithPath: try XCTUnwrap(conversation.workspacePath))
        test.model.inspector.developmentChanges = [
            try change(path: "Reports/Weekly review.md", before: nil),
            try change(path: "Sources/NativeApp/ReviewView.swift", before: "Existing source")
        ]
        try capture(
            VyronTaskOverviewView(),
            model: test.model,
            size: CGSize(width: 300, height: 520),
            to: directory.appendingPathComponent("overview-populated.png")
        )
        try capture(
            VyronConversationWindowView(conversationID: conversation.id),
            model: test.model,
            size: CGSize(width: 1000, height: 760),
            to: directory.appendingPathComponent("window-read-only.png")
        )
        let sideID = try XCTUnwrap(test.model.newSideChat(from: conversation.id))
        try capture(
            VyronConversationWindowView(conversationID: sideID),
            model: test.model,
            size: CGSize(width: 1000, height: 760),
            to: directory.appendingPathComponent("window-new-side-chat.png")
        )
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertFalse(test.model.isSideChatGenerating(sideID))
        XCTAssertEqual(test.model.selectedConversationID, conversation.id)
    }

    @discardableResult
    private func capture<Content: View>(
        _ content: Content,
        model: AppModel,
        size: CGSize,
        to url: URL
    ) throws -> CGImage {
        let renderer = ImageRenderer(content: content
            .environmentObject(model)
            .environment(\.locale, Locale(identifier: "en"))
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = 2
        let image = try XCTUnwrap(
            renderer.cgImage,
            "Offscreen ImageRenderer is unsupported here; no application/window fallback is permitted."
        )
        XCTAssertEqual(image.width, Int(size.width * renderer.scale))
        XCTAssertEqual(image.height, Int(size.height * renderer.scale))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
        return image
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
        var colorCounts: [UInt32: Int] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2])
            colorCounts[rgb, default: 0] += 1
        }
        let background = try XCTUnwrap(colorCounts.max { $0.value < $1.value }?.key)
        let backgroundBrightness = Int((background >> 16) & 255) + Int((background >> 8) & 255)
            + Int(background & 255)
        var foreground = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let brightness = Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
            if brightness - backgroundBrightness > 90 { foreground += 1 }
        }
        // Text must contribute meaningful bright foreground, rather than a successfully encoded flat background.
        return foreground >= max(200, image.width * image.height / 1_000)
    }

    private func populatedConversation() throws -> Conversation {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var activity = ResponseActivity(startedAt: start)
        for name in ["Review interface", "Check project"] {
            let identity = VyronSubagentIdentity(name: name, prompt: "Fixture review", model: "Fixture model")
            activity.recordSubagent(VyronSubagentEvent(identity: identity, update: .started, date: start))
            activity.recordSubagent(VyronSubagentEvent(
                identity: identity,
                update: .finished(VyronSubagentCompletion(state: .completed, summary: "Review complete.")),
                date: start.addingTimeInterval(600)
            ))
        }
        activity.record("Saved the review report.", at: start.addingTimeInterval(807))
        activity.finish(.completed, at: start.addingTimeInterval(807))
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aMioAAAAASUVORK5CYII="
        ))
        let images = (1...4).map { index in
            VyronImageAttachment(name: "Reference \(index).png", mimeType: "image/png", data: png)
        }
        var conversation = Conversation(title: "Review the native app", workspacePath: "/Fixture/NativeApp")
        conversation.mode = ComposerMode.agent.rawValue
        conversation.messages = [
            ChatMessage(role: "user", content: "Review the native interface and save a short report.", images: images),
            ChatMessage(
                role: "assistant",
                content: "The review is complete. The report is saved in `Reports/Weekly review.md`.\n\n"
                    + "- Native controls remain aligned.\n- The original task and its evidence are preserved.",
                activity: activity
            )
        ]
        return conversation
    }

    private func change(path: String, before: String?) throws -> DevelopmentChange {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "path": path, "before": before as Any? ?? NSNull(),
            "after": "Fixture output", "unifiedDiff": "Fixture diff"
        ])
        return try JSONDecoder().decode(DevelopmentChange.self, from: data)
    }
}
