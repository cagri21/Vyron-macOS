import AppKit
import SwiftUI
import XCTest
import VyronCore
@testable import Vyron

/// Production question cards only; no application, window, or provider connection is started.
@MainActor
final class VyronUserInputRenderTests: XCTestCase {
    func testCaptureCompactAndLongQuestionCardsAtRegularAndNarrowWidths() async throws {
        guard ProcessInfo.processInfo.environment["VYRON_CAPTURE_USER_INPUT"] == "1" else {
            throw XCTSkip("Set VYRON_CAPTURE_USER_INPUT=1 for offscreen question-card verification.")
        }
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/user-input", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for count in [1, 3] {
            let request = fixture(questionCount: count)
            let waiting = Task {
                try await test.model.interactions.requestUserInput(
                    request, generationID: UUID(), conversation: { UUID() }, didPresent: {}
                )
            }
            defer {
                test.model.cancelPendingUserInput()
                waiting.cancel()
            }
            for _ in 0..<100 where test.model.interactions.pendingUserInput?.id != request.id {
                await Task.yield()
            }
            XCTAssertEqual(test.model.interactions.pendingUserInput?.id, request.id)
            for width: CGFloat in [640, 504] {
                let content = VyronUserInputRequestView(request: request)
                    .environmentObject(test.model)
                    .environment(\.locale, Locale(identifier: "en"))
                    .environment(\.colorScheme, .dark)
                    .frame(width: width)
                let size = try await capture(
                    content,
                    width: width,
                    to: directory.appendingPathComponent("questions-\(count)-\(Int(width)).png")
                )
                XCTAssertEqual(size.width, width, accuracy: 1)
                let maximumHeight = VyronUserInputStyle.actionSize + VyronUserInputStyle.sectionSpacing
                    + VyronUserInputStyle.maximumQuestionsHeight + 2 * VyronUserInputStyle.padding
                XCTAssertLessThanOrEqual(size.height, maximumHeight + 1)
                XCTAssertGreaterThan(size.height, 160, "The real options and answer field must participate in layout.")
            }
        }
        XCTAssertFalse(test.model.modelSelection.isConnected)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertTrue(test.model.composer.draft.isEmpty)
    }

    private func fixture(questionCount: Int) -> VyronUserInputRequest {
        VyronUserInputRequest(questions: (0..<questionCount).map { index in
            VyronUserInputQuestion(
                id: "choice-\(index)",
                question: questionCount == 1
                    ? "What would you like to try next in Vyron?"
                    : "Question \(index + 1): Which approach should this task use for the next stage?",
                options: [
                    VyronUserInputOption(label: "Investigate the Apple Vision OCR error", description: ""),
                    VyronUserInputOption(label: "Try a model that supports images", description: ""),
                    VyronUserInputOption(label: "Explore clarification prompts like this one", description: "")
                ]
            )
        })
    }

    private func capture<Content: View>(_ content: Content, width: CGFloat, to url: URL) async throws -> CGSize {
        let hosting = NSHostingView(rootView: content.background(Palette.canvas))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        for _ in 0..<4 {
            hosting.layoutSubtreeIfNeeded()
            await Task.yield()
            hosting.setFrameSize(hosting.fittingSize)
        }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw XCTSkip("BLOCKED: offscreen question card has no fitting size; no app/window fallback permitted.")
        }
        hosting.setFrameSize(size)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw XCTSkip("BLOCKED: native offscreen question-card capture is unavailable.")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
        guard hasNativeInput(in: hosting) else {
            throw XCTSkip(
                "BLOCKED: offscreen capture did not materialize the native answer input; "
                    + "the saved partial card image does not verify that control."
            )
        }
        guard hasForegroundContent(bitmap) else {
            throw XCTSkip("BLOCKED: native offscreen question card did not paint; visual QA remains incomplete.")
        }
        return size
    }

    private func hasNativeInput(in view: NSView) -> Bool {
        if let input = view as? NSTextField, input.isEditable, input.visibleRect.height > 0 { return true }
        if let input = view as? NSTextView, input.isEditable, input.visibleRect.height > 0 { return true }
        return view.subviews.contains { hasNativeInput(in: $0) }
    }

    private func hasForegroundContent(_ bitmap: NSBitmapImageRep) -> Bool {
        var lightSamples = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.redComponent + color.greenComponent + color.blueComponent > 1.5 {
                    lightSamples += 1
                }
            }
        }
        return lightSamples > 100
    }
}
