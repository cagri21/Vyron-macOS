import AppKit
import SwiftUI
import XCTest
@testable import Vyron

/// Offscreen fixtures check that the terminal shares vertical space with the conversation.
@MainActor
final class VyronWorkspaceTerminalSplitRenderTests: XCTestCase {
    func testOpeningTerminalPlacesItBelowTheConversationAtItsDefaultHeight() throws {
        let image = try render(isPresented: true, height: 600)

        try assertConversation(in: image, at: [0, 200, 402])
        try assertTerminal(in: image, at: [406, 500, 599])
    }

    func testClosingTerminalReturnsItsEntireHeightToTheConversation() throws {
        let image = try render(isPresented: false, height: 600)

        try assertConversation(in: image, at: [0, 200, 404, 405, 599])
    }

    func testShorterWorkspaceReservesUsableConversationHeight() throws {
        let image = try render(isPresented: true, height: 450)

        try assertConversation(in: image, at: [0, 150, 299])
        try assertTerminal(in: image, at: [302, 400, 449])
    }

    func testTerminalCanShrinkBelowItsMinimumWhenTheWindowIsConstrained() throws {
        let image = try render(isPresented: true, height: 360)

        try assertConversation(in: image, at: [0, 150, 299])
        try assertTerminal(in: image, at: [302, 330, 359])
    }

    func testVeryShortWorkspaceDoesNotLetTerminalOverflowTheConversation() throws {
        let image = try render(isPresented: true, height: 200)

        try assertConversation(in: image, at: [0, 100, 198])
    }

    private func render(isPresented: Bool, height: CGFloat) throws -> NSBitmapImageRep {
        let split = VyronWorkspaceTerminalSplitView(isPresented: isPresented) {
            Color(nsColor: .red)
        } content: {
            Color(nsColor: .green)
        }
        let renderer = ImageRenderer(content: split.frame(width: 80, height: height))
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            throw XCTSkip("BLOCKED: Offscreen ImageRenderer unavailable; no application/window fallback permitted.")
        }
        XCTAssertEqual(image.width, 80)
        XCTAssertEqual(image.height, Int(height))
        return NSBitmapImageRep(cgImage: image)
    }

    private func assertConversation(in image: NSBitmapImageRep, at rows: [Int]) throws {
        for y in rows {
            let sample = try color(in: image, at: y)
            XCTAssertGreaterThan(sample.greenComponent, 0.9, "Expected conversation at row \(y).")
            XCTAssertLessThan(sample.redComponent, 0.1, "Terminal overlapped the conversation at row \(y).")
        }
    }

    private func assertTerminal(in image: NSBitmapImageRep, at rows: [Int]) throws {
        for y in rows {
            let sample = try color(in: image, at: y)
            XCTAssertGreaterThan(sample.redComponent, 0.9, "Expected terminal at row \(y).")
            XCTAssertLessThan(sample.greenComponent, 0.1, "Conversation overlapped the terminal at row \(y).")
        }
    }

    private func color(in image: NSBitmapImageRep, at y: Int) throws -> NSColor {
        try XCTUnwrap(image.colorAt(x: 40, y: y)?.usingColorSpace(.deviceRGB))
    }
}
