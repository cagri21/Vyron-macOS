import AppKit
import SwiftUI
import XCTest
import VyronDevelopment
@testable import Vyron

@MainActor
final class VyronConversationChangesRenderTests: XCTestCase {
    func testRenderChangesCardAndHoverPreview() async throws {
        let change = try fixture(
            path: "Apps/Vyron/Views/Conversation/Components/VyronConversationChangesCard.swift",
            before: "struct ChangesCard {\n    let title = \"Changes\"\n}\n",
            after: "struct ChangesCard {\n    let title = \"Edited files\"\n    let showsCounts = true\n}\n"
        )
        let added = try fixture(path: "Tests/VyronTests/ChangePreviewTests.swift", after: "import XCTest\n")
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/verification/conversation-changes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for width: CGFloat in [640, 400] {
            let card = VyronConversationChangesCard(changes: [change, added], open: { _ in }, undo: {})
            try await capture(
                card, width: width, destination: directory.appendingPathComponent("card-\(Int(width)).png")
            )
            let diff = VyronUnifiedDiff(
                change: change, maximumLineCount: VyronConversationChangesStyle.previewLineCount
            )
            let preview = VyronConversationChangePreview(path: change.path, diff: diff)
            XCTAssertEqual(diff.addedCount, 2)
            XCTAssertEqual(diff.removedCount, 1)
            try await capture(
                preview, width: width, destination: directory.appendingPathComponent("hover-preview-\(Int(width)).png")
            )
        }
    }

    private func fixture(path: String, before: String? = nil, after: String) throws -> DevelopmentChange {
        var fields = ["id": UUID().uuidString, "path": path, "after": after, "unifiedDiff": ""]
        fields["before"] = before
        let data = try JSONEncoder().encode(fields)
        return try JSONDecoder().decode(DevelopmentChange.self, from: data)
    }

    private func capture<Content: View>(_ content: Content, width: CGFloat, destination: URL) async throws {
        let hosting = NSHostingView(rootView: content
            .environment(\.colorScheme, .dark)
            .frame(width: width)
            .background(Palette.canvas))
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(15))
            hosting.setFrameSize(hosting.fittingSize)
        }
        let size = hosting.fittingSize
        XCTAssertEqual(size.width, width, accuracy: 1)
        XCTAssertGreaterThan(size.height, 80)
        XCTAssertLessThan(size.height, 250)
        hosting.setFrameSize(size)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw XCTSkip("Offscreen Changes capture unavailable.")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: destination, options: .atomic)
        XCTAssertTrue(containsChangeColors(bitmap), "The rendered changes must paint both addition and removal colors.")
    }

    private func containsChangeColors(_ bitmap: NSBitmapImageRep) -> Bool {
        var foundAddition = false
        var foundRemoval = false
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                foundAddition = foundAddition || color.greenComponent - color.redComponent > 0.35
                foundRemoval = foundRemoval || color.redComponent - color.greenComponent > 0.35
                if foundAddition && foundRemoval { return true }
            }
        }
        return false
    }
}
